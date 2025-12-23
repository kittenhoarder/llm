#!/usr/bin/env python3
"""
LEANN Bridge - Python bridge for code indexing and search
This script provides a simple interface for Swift to interact with LEANN
"""

import json
import sys
import os
from pathlib import Path
from typing import List, Dict, Any, Optional
import argparse

# Import LEANN components
import os
import re

# Suppress library logs and warnings before importing them
os.environ["TOKENIZERS_PARALLELISM"] = "false"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
import logging
logging.getLogger("leann").setLevel(logging.ERROR)
logging.getLogger("sentence_transformers").setLevel(logging.ERROR)

from leann import LeannBuilder, LeannSearcher
import contextlib
import io

@contextlib.contextmanager
def suppress_stdout():
    """Redirects stdout to stderr at the OS level to catch C++ extension output"""
    # Duplicate original stdout (fd 1) so we can restore it later
    original_stdout_fd = os.dup(1)
    try:
        # Redirect fd 1 (stdout) to fd 2 (stderr)
        os.dup2(2, 1)
        yield
    finally:
        # Flush everything before restoring
        sys.stdout.flush()
        sys.stderr.flush()
        # Restore original stdout
        os.dup2(original_stdout_fd, 1)
        os.close(original_stdout_fd)

def print_result(result):
    """Print result wrapped in markers for easy parsing in Swift"""
    print("---JSON_START---")
    print(json.dumps(result, indent=2))
    print("---JSON_END---")


class LEANNBridge:
    """Bridge between Swift and LEANN Python library"""
    
    def __init__(self, index_path: str = "./leann_index"):
        self.index_path = Path(index_path)
        # Only create the parent directory, not the index path itself as a directory
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        
    def index_codebase(
        self,
        root_path: str,
        extensions: Optional[List[str]] = None,
        exclude_dirs: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Index a codebase with metadata
        
        Args:
            root_path: Root directory of codebase
            extensions: File extensions to index (e.g., ['.swift', '.py'])
            exclude_dirs: Directories to exclude
            
        Returns:
            Statistics about indexing operation
        """
        if extensions is None:
            extensions = ['.swift', '.py', '.js', '.ts', '.md', '.json', '.csv', '.yaml', '.yml', '.txt']
        if exclude_dirs is None:
            exclude_dirs = ['build', '.build', 'node_modules', 'venv', '.git']
            
        root = Path(root_path)
        if not root.exists():
            return {"error": f"Path does not exist: {root_path}"}
            
        # Initialize builder with on-device sentence-transformers model
        # is_recompute=False and is_compact=False ensure that we store full embeddings
        # so that searches can be performed in-process without an embedding server.
        builder = LeannBuilder(
            backend_name="hnsw",
            embedding_model="sentence-transformers/all-MiniLM-L6-v2",  # Fast, local, on-device
            is_recompute=False,
            is_compact=False
        )
        
        indexed_files = 0
        indexed_chunks = 0
        errors = []
        
        # Walk through directory
        for file_path in root.rglob('*'):
            # Skip if not a file
            if not file_path.is_file():
                continue
                
            # Skip excluded directories
            if any(exc in file_path.parts for exc in exclude_dirs):
                continue
                
            # Skip if not matching extension
            if file_path.suffix not in extensions:
                continue
                
            try:
                # Read file content
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    
                # Skip empty files
                if not content.strip():
                    continue
                    
                # Get file metadata
                stat = file_path.stat()
                rel_path = str(file_path.relative_to(root))
                
                metadata = {
                    "file_path": rel_path,
                    "file_extension": file_path.suffix,
                    "file_name": file_path.name,
                    "file_size": stat.st_size,
                    "last_modified": stat.st_mtime,
                }
                
                # Index the file
                # LEANN will automatically chunk long files
                builder.add_text(content, metadata=metadata)
                
                indexed_files += 1
                indexed_chunks += 1  # Simplified - LEANN handles chunking internally
                
            except Exception as e:
                errors.append(f"Error indexing {file_path}: {str(e)}")
                
        # Build the index
        try:
            builder.build_index(str(self.index_path))
        except Exception as e:
            return {"error": f"Failed to build index: {str(e)}"}

            
        return {
            "success": True,
            "indexed_files": indexed_files,
            "indexed_chunks": indexed_chunks,
            "errors": errors,
            "index_path": str(self.index_path)
        }
        

    def search(
        self,
        query: str,
        top_k: int = 10,
        metadata_filters: Optional[Dict[str, Any]] = None,
        use_grep: bool = False
    ) -> List[Dict[str, Any]]:
        """
        Search the indexed codebase
        
        Args:
            query: Search query
            top_k: Number of results to return
            metadata_filters: Filters to apply (e.g., {"file_extension": {"==": ".swift"}})
            use_grep: Use exact text matching instead of semantic search
            
        Returns:
            List of search results with content and metadata
        """
        try:
            # Initialize searcher with index path
            searcher = LeannSearcher(str(self.index_path))
            
            # Check if index requires recompute
            # This is true for pruned or compact HNSW indices
            # If so, we MUST set recompute_embeddings=True
            is_pruned = searcher.meta_data.get("is_pruned", False)
            is_compact = searcher.meta_data.get("is_compact", False)
            recompute_required = is_pruned or is_compact
            
            # Perform search
            # If recompute is NOT required, we use in-process embedding computation
            # which is much more reliable in a sandboxed environment.
            try:
                results = searcher.search(
                    query=query,
                    top_k=top_k,
                    metadata_filters=metadata_filters,
                    use_grep=use_grep,
                    recompute_embeddings=recompute_required
                )
            except Exception as search_err:
                # If grep failed due to missing file (library bug), try manual fallback
                if use_grep and "No .jsonl passages file found" in str(search_err):
                    return self._manual_grep(query, top_k)
                    
                # If search failed and it required recompute, it's likely the server failed
                if recompute_required:
                    return [{"error": f"Search failed because the index is compact/pruned and the recompute server could not start. Please RE-INDEX your codebase in Settings for better performance and reliability. Error: {str(search_err)}"}]
                raise search_err
            
            # Format results
            formatted_results = []
            for result in results:
                formatted_results.append({
                    "content": result.text,
                    "metadata": result.metadata,
                    "score": float(result.score),  # Convert numpy float32 to Python float
                })
                
            return formatted_results
            
        except Exception as e:
            if use_grep and "No .jsonl passages file found" in str(e):
                 return self._manual_grep(query, top_k)
            return [{"error": f"Search failed: {str(e)}"}]

    def _manual_grep(self, query: str, top_k: int) -> List[Dict[str, Any]]:
        """Fallback manual grep implementation to bypass library issues"""
        try:
            # Try to find metadata file
            meta_path = Path(str(self.index_path) + ".meta.json")
            if not meta_path.exists():
                 # Try inside directory if it was a dir
                 meta_path = self.index_path / "meta.json"
                 if not meta_path.exists():
                     meta_path = self.index_path / "code_index.meta.json"
            
            if not meta_path.exists():
                 return [{"error": f"Grep failed: Metadata not found at {self.index_path}[.meta.json]"}]
                 
            with open(meta_path, 'r') as f:
                meta = json.load(f)
                
            passage_path = None
            if "passage_sources" in meta:
                for src in meta["passage_sources"]:
                    if src.get("type") == "jsonl":
                        passage_path = src.get("path")
                        break
            
            if not passage_path:
                return [{"error": "Grep failed: No jsonl passage source found in metadata"}]
                
            # Resolve passage path
            # 1. Try relative to metadata file directory
            pass_file = meta_path.parent / passage_path
            
            if not pass_file.exists():
                 # 2. Try absolute path
                 pass_file = Path(passage_path)
            
            if not pass_file.exists() and not Path(passage_path).is_absolute():
                 # 3. Try relative to CWD?
                 pass_file = Path(passage_path)
                 
            if not pass_file.exists():
                return [{"error": f"Grep failed: Passage file not found at {pass_file} or {passage_path}"}]
                
            results = []
            try:
                pattern = re.compile(query, re.IGNORECASE)
            except re.error as e:
                return [{"error": f"Invalid regex pattern: {str(e)}"}]
            
            with open(pass_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    try:
                        record = json.loads(line)
                        # Content field might vary
                        content = record.get("text") or record.get("content") or ""
                        
                        if pattern.search(content):
                            # Ensure metadata exists
                            metadata = record.get("metadata", {})
                            
                            results.append({
                                "content": content,
                                "metadata": metadata,
                                "score": 1.0
                            })
                            if len(results) >= top_k:
                                break
                    except:
                        continue
                        
            if not results:
                 # Return empty list instead of error for no matches
                 return []
                 
            return results
        except Exception as e:
            return [{"error": f"Manual grep fallback failed: {str(e)}"}]
            
    def get_index_stats(self) -> Dict[str, Any]:
        """Get statistics about the index"""
        try:
            if not self.index_path.exists():
                return {"error": "Index does not exist"}
                
            # Calculate index size
            total_size = sum(
                f.stat().st_size
                for f in self.index_path.rglob('*')
                if f.is_file()
            )
            
            return {
                "index_path": str(self.index_path),
                "index_size_bytes": total_size,
                "index_size_mb": round(total_size / (1024 * 1024), 2),
                "exists": True
            }
            
        except Exception as e:
            return {"error": f"Failed to get stats: {str(e)}"}

    def list_files(self) -> List[str]:
        """List all indexed file paths (extracted from metadata)"""
        try:
            searcher = LeannSearcher(str(self.index_path))
            # LEANN doesn't have a direct 'list all metadata' but we can 
            # infer it from the internal storage or just search for everything
            # For now, let's just return a placeholder or implement if LEANN supports it
            # Actually, let's use a simpler approach: return the files that match the index criteria
            # in the saved path if we had it, but here we only have the index.
            
            # If LeannSearcher exposes the metadata storage, we'd use it.
            # Assuming we want a list of files that WERE indexed:
            return ["file_list_not_implemented_in_leann_yet"]
            
        except Exception as e:
            return [f"Error listing files: {str(e)}"]


def main():
    """Command-line interface for LEANN bridge"""
    parser = argparse.ArgumentParser(description="LEANN Bridge for Swift integration")
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Index command
    index_parser = subparsers.add_parser('index', help='Index a codebase')
    index_parser.add_argument('path', help='Path to codebase root')
    index_parser.add_argument('--extensions', nargs='+', help='File extensions to index')
    index_parser.add_argument('--exclude', nargs='+', help='Directories to exclude')
    index_parser.add_argument('--index-path', default='./leann_index', help='Path to store index')
    
    # Search command
    search_parser = subparsers.add_parser('search', help='Search the index')
    search_parser.add_argument('query', help='Search query')
    search_parser.add_argument('--top-k', type=int, default=10, help='Number of results')
    search_parser.add_argument('--grep', action='store_true', help='Use exact text matching')
    search_parser.add_argument('--filter', help='JSON metadata filter')
    search_parser.add_argument('--index-path', default='./leann_index', help='Path to index')
    
    # Stats command
    stats_parser = subparsers.add_parser('stats', help='Get index statistics')
    stats_parser.add_argument('--index-path', default='./leann_index', help='Path to index')
    
    args = parser.parse_args()
    
    if args.command == 'index':
        with suppress_stdout():
            bridge = LEANNBridge(index_path=args.index_path)
            result = bridge.index_codebase(
                root_path=args.path,
                extensions=args.extensions,
                exclude_dirs=args.exclude
            )
        print_result(result)
        
    elif args.command == 'search':
        with suppress_stdout():
            bridge = LEANNBridge(index_path=args.index_path)
            metadata_filters = None
            if args.filter:
                try:
                    metadata_filters = json.loads(args.filter)
                except:
                    pass
            results = bridge.search(
                query=args.query,
                top_k=args.top_k,
                metadata_filters=metadata_filters,
                use_grep=args.grep
            )
        print_result(results)
        
    elif args.command == 'stats':
        with suppress_stdout():
            bridge = LEANNBridge(index_path=args.index_path)
            stats = bridge.get_index_stats()
        print_result(stats)
        
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
