# Known Issues

## SQLite.swift Package Warning

**Warning**: `'sqlite.swift': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target`

**File**: `/Users/owenperry/dev/llm/.build/checkouts/SQLite.swift/Sources/SQLite/PrivacyInfo.xcprivacy`

**Status**: Known issue in dependency, cannot be fixed without modifying the upstream package

**Impact**: Non-critical - this is a harmless warning that doesn't affect functionality. The privacy file is part of the SQLite.swift dependency and is properly handled by the package when used in Xcode projects.

**Workaround**: None required - the warning can be safely ignored. This will likely be fixed in a future version of SQLite.swift.

**Reference**: This is a common issue with Swift Package Manager when dependencies include privacy manifest files that aren't explicitly declared as resources.

