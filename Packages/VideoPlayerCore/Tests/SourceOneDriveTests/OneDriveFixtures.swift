import Foundation

// FIXTURES: HAND-WRITTEN FROM MICROSOFT'S DOCUMENTATION. They are NOT recorded from the real
// service. No Microsoft app is registered and Microsoft was never contacted, so these only prove
// that the client handles the response shapes the documentation describes. Field names and
// error codes follow the Microsoft identity platform device-code docs and the Graph driveItem
// docs as remembered; real responses may differ (extra fields, different casing or ordering).
enum OneDriveFixtures {
    static let deviceCode = """
    {"user_code":"FJH2K9XQ","device_code":"DAQABAAEAAAD--DLA3VO7QrddgJg7WevrDEVICE","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":5,"message":"To sign in, use a web browser to open the page https://www.microsoft.com/link and enter the code FJH2K9XQ to authenticate."}
    """

    static let tokens = """
    {"token_type":"Bearer","scope":"Files.Read offline_access","expires_in":3599,"access_token":"ACCESS-1","refresh_token":"REFRESH-1"}
    """

    static let refreshedTokens = """
    {"token_type":"Bearer","scope":"Files.Read offline_access","expires_in":3599,"access_token":"ACCESS-2","refresh_token":"REFRESH-2"}
    """

    static let refreshedNoNewRefresh = """
    {"token_type":"Bearer","expires_in":3599,"access_token":"ACCESS-3"}
    """

    static func error(_ code: String) -> String {
        "{\"error\":\"\(code)\",\"error_description\":\"hand-written fixture\"}"
    }

    static let drive = #"{"id":"b!drive1","driveType":"personal"}"#

    static let rootItem = #"{"id":"ROOT1","name":"root","folder":{"childCount":2},"eTag":"\"{R},1\"","cTag":"\"c:{R},1\""}"#

    /// First page of root children, with a continuation link.
    static let rootChildrenPage1 = """
    {"@odata.context":"https://graph.microsoft.com/v1.0/$metadata#users('me')/drive/root/children",
     "@odata.nextLink":"https://graph.microsoft.com/v1.0/me/drive/root/children?$skiptoken=PAGE2",
     "value":[
      {"id":"F-MOVIES","name":"Movies","size":0,"eTag":"\\"{M},3\\"","cTag":"\\"c:{M},3\\"","lastModifiedDateTime":"2024-03-02T10:00:00Z","folder":{"childCount":2}}
     ]}
    """

    static let rootChildrenPage2 = """
    {"value":[
      {"id":"I-FILM","name":"The Quiet Harbor (2019).mkv","size":123456789,"eTag":"\\"{A},5\\"","cTag":"\\"c:{A},7\\"","lastModifiedDateTime":"2024-03-02T10:15:30.123Z","file":{"mimeType":"video/x-matroska"},"@microsoft.graph.downloadUrl":"https://download.example.test/film?tempauth=T1"}
    ]}
    """

    static let moviesChildren = """
    {"value":[
      {"id":"I-EP1","name":"Episode 1.mp4","size":1000,"eTag":"\\"{E},1\\"","cTag":"\\"c:{E},1\\"","lastModifiedDateTime":"2024-05-01T08:00:00Z","file":{"mimeType":"video/mp4"},"@microsoft.graph.downloadUrl":"https://download.example.test/ep1?tempauth=E1"},
      {"id":"F-S1","name":"Season 1","eTag":"\\"{S},1\\"","cTag":"\\"c:{S},1\\"","lastModifiedDateTime":"2024-05-01T08:00:00Z","folder":{"childCount":0}}
    ]}
    """

    static let moviesFolderItem = #"{"id":"F-MOVIES","name":"Movies","folder":{"childCount":2},"eTag":"\"{M},3\"","cTag":"\"c:{M},3\""}"#

    static func fileItem(downloadURL: String) -> String {
        """
        {"id":"I-FILM","name":"The Quiet Harbor (2019).mkv","size":123456789,"eTag":"\\"{A},5\\"","cTag":"\\"c:{A},7\\"","lastModifiedDateTime":"2024-03-02T10:15:30Z","file":{"mimeType":"video/x-matroska"},"@microsoft.graph.downloadUrl":"\(downloadURL)"}
        """
    }
}
