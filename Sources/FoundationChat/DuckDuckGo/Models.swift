//
//  Models.swift
//  FoundationChat
//
//  Models for DuckDuckGo Instant Answers API responses
//

import Foundation

/// Main response structure from DuckDuckGo Instant Answers API
public struct DuckDuckGoResponse: Codable, Sendable {
    /// Direct answer (for calculations, definitions, etc.)
    public let answer: String?
    
    /// Type of answer (e.g., "calc", "definition", "answer")
    public let answerType: String?
    
    /// Main abstract text
    public let abstract: String?
    
    /// Full abstract content
    public let abstractText: String?
    
    /// Source URL for the abstract
    public let abstractURL: String?
    
    /// Source name
    public let abstractSource: String?
    
    /// Image URL if available
    public let image: String?
    
    /// Heading for the abstract
    public let heading: String?
    
    /// Related topics array
    public let relatedTopics: [RelatedTopic]?
    
    /// Results array (for some response types)
    public let results: [Result]?
    
    /// Definition text
    public let definition: String?
    
    /// Definition source URL
    public let definitionURL: String?
    
    /// Definition source name
    public let definitionSource: String?
    
    /// Entity type (e.g., "D")
    public let entity: String?
    
    /// Meta information
    public let meta: Meta?
    
    enum CodingKeys: String, CodingKey {
        case answer = "Answer"
        case answerType = "AnswerType"
        case abstract = "Abstract"
        case abstractText = "AbstractText"
        case abstractURL = "AbstractURL"
        case abstractSource = "AbstractSource"
        case image = "Image"
        case heading = "Heading"
        case relatedTopics = "RelatedTopics"
        case results = "Results"
        case definition = "Definition"
        case definitionURL = "DefinitionURL"
        case definitionSource = "DefinitionSource"
        case entity = "Entity"
        case meta = "meta"
    }
    
    /// Check if response has any useful content
    public var hasContent: Bool {
        return answer != nil && !answer!.isEmpty
            || abstract != nil && !abstract!.isEmpty
            || abstractText != nil && !abstractText!.isEmpty
            || definition != nil && !definition!.isEmpty
            || (relatedTopics != nil && !relatedTopics!.isEmpty)
    }
}

/// Related topic from DuckDuckGo API
public struct RelatedTopic: Codable, Sendable {
    /// First URL in the topic
    public let firstURL: String?
    
    /// Icon information
    public let icon: Icon?
    
    /// Result text
    public let result: String?
    
    /// Text content
    public let text: String?
    
    enum CodingKeys: String, CodingKey {
        case firstURL = "FirstURL"
        case icon = "Icon"
        case result = "Result"
        case text = "Text"
    }
}

/// Icon information
public struct Icon: Codable, Sendable {
    /// Height of the icon
    public let height: String?
    
    /// URL of the icon
    public let url: String?
    
    /// Width of the icon
    public let width: String?
    
    enum CodingKeys: String, CodingKey {
        case height = "Height"
        case url = "URL"
        case width = "Width"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle height as either String or Int
        if let heightString = try? container.decode(String.self, forKey: .height) {
            height = heightString
        } else if let heightInt = try? container.decode(Int.self, forKey: .height) {
            height = String(heightInt)
        } else {
            height = nil
        }
        
        // Handle width as either String or Int
        if let widthString = try? container.decode(String.self, forKey: .width) {
            width = widthString
        } else if let widthInt = try? container.decode(Int.self, forKey: .width) {
            width = String(widthInt)
        } else {
            width = nil
        }
        
        url = try? container.decode(String.self, forKey: .url)
    }
}

/// Result item
public struct Result: Codable, Sendable {
    /// First URL
    public let firstURL: String?
    
    /// Icon information
    public let icon: Icon?
    
    /// Result text
    public let result: String?
    
    /// Text content
    public let text: String?
    
    enum CodingKeys: String, CodingKey {
        case firstURL = "FirstURL"
        case icon = "Icon"
        case result = "Result"
        case text = "Text"
    }
}

/// Meta information
public struct Meta: Codable, Sendable {
    /// Developer attribution
    public let developer: [Developer]?
    
    /// Maintainer information
    public let maintainer: Maintainer?
    
    /// Attribution information
    public let attribution: String?
    
    /// Example queries
    public let exampleQuery: String?
    
    /// Source name
    public let srcName: String?
    
    /// Source domain
    public let srcDomain: String?
    
    /// Source options
    public let srcOptions: SrcOptions?
    
    /// Source ID
    public let srcID: Int?
    
    /// Source URL
    public let srcURL: String?
    
    /// Signal from
    public let signalFrom: String?
    
    /// Block group
    public let blockgroup: String?
    
    /// Created date
    public let createdDate: String?
    
    /// Start date
    public let startDate: String?
    
    /// Number of results
    public let num: Int?
    
    /// Designation
    public let designation: String?
    
    /// ID
    public let id: String?
    
    /// Name
    public let name: String?
    
    /// Topic (can be String or Array)
    public let topic: String?
    
    /// Production state
    public let productionState: String?
    
    /// Tab
    public let tab: String?
    
    /// Unsafe
    public let unsafe: Int?
    
    /// Status
    public let status: String?
    
    enum CodingKeys: String, CodingKey {
        case developer
        case maintainer
        case attribution
        case exampleQuery = "example_query"
        case srcName = "src_name"
        case srcDomain = "src_domain"
        case srcOptions = "src_options"
        case srcID = "src_id"
        case srcURL = "src_url"
        case signalFrom = "signal_from"
        case blockgroup
        case createdDate = "created_date"
        case startDate = "start_date"
        case num
        case designation
        case id
        case name
        case topic
        case productionState = "production_state"
        case tab
        case unsafe
        case status
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        developer = try? container.decode([Developer].self, forKey: .developer)
        maintainer = try? container.decode(Maintainer.self, forKey: .maintainer)
        attribution = try? container.decode(String.self, forKey: .attribution)
        exampleQuery = try? container.decode(String.self, forKey: .exampleQuery)
        srcName = try? container.decode(String.self, forKey: .srcName)
        srcDomain = try? container.decode(String.self, forKey: .srcDomain)
        srcOptions = try? container.decode(SrcOptions.self, forKey: .srcOptions)
        srcID = try? container.decode(Int.self, forKey: .srcID)
        srcURL = try? container.decode(String.self, forKey: .srcURL)
        signalFrom = try? container.decode(String.self, forKey: .signalFrom)
        blockgroup = try? container.decode(String.self, forKey: .blockgroup)
        createdDate = try? container.decode(String.self, forKey: .createdDate)
        startDate = try? container.decode(String.self, forKey: .startDate)
        num = try? container.decode(Int.self, forKey: .num)
        designation = try? container.decode(String.self, forKey: .designation)
        id = try? container.decode(String.self, forKey: .id)
        name = try? container.decode(String.self, forKey: .name)
        productionState = try? container.decode(String.self, forKey: .productionState)
        tab = try? container.decode(String.self, forKey: .tab)
        unsafe = try? container.decode(Int.self, forKey: .unsafe)
        status = try? container.decode(String.self, forKey: .status)
        
        // Handle topic as either String or Array
        if let topicString = try? container.decode(String.self, forKey: .topic) {
            topic = topicString
        } else if let topicArray = try? container.decode([String].self, forKey: .topic) {
            topic = topicArray.joined(separator: ", ")
        } else {
            topic = nil
        }
    }
}

/// Developer information
public struct Developer: Codable, Sendable {
    /// Name
    public let name: String?
    
    /// Type
    public let type: String?
    
    /// URL
    public let url: String?
}

/// Maintainer information
public struct Maintainer: Codable, Sendable {
    /// GitHub username
    public let github: String?
}

/// Source options
public struct SrcOptions: Codable, Sendable {
    /// Directory
    public let directory: String?
    
    /// Is fuzzy
    public let isFuzzy: Bool?
    
    /// Is mediawiki
    public let isMediawiki: Bool?
    
    /// Is Wikipedia
    public let isWikipedia: Bool?
    
    /// Language
    public let language: String?
    
    /// Min abstract length
    public let minAbstractLength: String?
    
    /// Skip abstract
    public let skipAbstract: Int?
    
    /// Skip abstract punctuation
    public let skipAbstractPunctuation: Int?
    
    /// Skip end
    public let skipEnd: String?
    
    /// Skip icon
    public let skipIcon: Int?
    
    /// Skip image name
    public let skipImageName: Int?
    
    /// Skip qr
    public let skipQr: String?
    
    /// Source skip
    public let sourceSkip: String?
    
    /// Src info
    public let srcInfo: String?
    
    enum CodingKeys: String, CodingKey {
        case directory
        case isFuzzy = "is_fuzzy"
        case isMediawiki = "is_mediawiki"
        case isWikipedia = "is_wikipedia"
        case language
        case minAbstractLength = "min_abstract_length"
        case skipAbstract = "skip_abstract"
        case skipAbstractPunctuation = "skip_abstract_punctuation"
        case skipEnd = "skip_end"
        case skipIcon = "skip_icon"
        case skipImageName = "skip_image_name"
        case skipQr = "skip_qr"
        case sourceSkip = "source_skip"
        case srcInfo = "src_info"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        directory = try? container.decode(String.self, forKey: .directory)
        language = try? container.decode(String.self, forKey: .language)
        minAbstractLength = try? container.decode(String.self, forKey: .minAbstractLength)
        skipAbstract = try? container.decode(Int.self, forKey: .skipAbstract)
        skipAbstractPunctuation = try? container.decode(Int.self, forKey: .skipAbstractPunctuation)
        skipEnd = try? container.decode(String.self, forKey: .skipEnd)
        skipIcon = try? container.decode(Int.self, forKey: .skipIcon)
        skipImageName = try? container.decode(Int.self, forKey: .skipImageName)
        skipQr = try? container.decode(String.self, forKey: .skipQr)
        sourceSkip = try? container.decode(String.self, forKey: .sourceSkip)
        srcInfo = try? container.decode(String.self, forKey: .srcInfo)
        
        // Handle boolean fields that may come as 0/1 integers
        if let fuzzyInt = try? container.decode(Int.self, forKey: .isFuzzy) {
            isFuzzy = fuzzyInt != 0
        } else {
            isFuzzy = try? container.decode(Bool.self, forKey: .isFuzzy)
        }
        
        if let mediawikiInt = try? container.decode(Int.self, forKey: .isMediawiki) {
            isMediawiki = mediawikiInt != 0
        } else {
            isMediawiki = try? container.decode(Bool.self, forKey: .isMediawiki)
        }
        
        if let wikipediaInt = try? container.decode(Int.self, forKey: .isWikipedia) {
            isWikipedia = wikipediaInt != 0
        } else {
            isWikipedia = try? container.decode(Bool.self, forKey: .isWikipedia)
        }
    }
}

