// Real responses recorded from "rclone serve dlna" (rclone v1.76.0) on 127.0.0.1. No credentials in them.
// The test server serves the generated media in ~/video-player-test-servers/data.

let rcloneDeviceDescription = #"""
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"
      xmlns:dlna="urn:schemas-dlna-org:device-1-0"
      xmlns:sec="http://www.sec.co.kr/dlna">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
    <friendlyName>VP Test Media</friendlyName>
    <manufacturer>rclone (rclone.org)</manufacturer>
    <manufacturerURL>https://rclone.org/</manufacturerURL>
    <modelDescription>rclone</modelDescription>
    <modelName>rclone</modelName>
    <modelNumber>v1.76.0</modelNumber>
    <modelURL>https://rclone.org/</modelURL>
    <serialNumber>00000000</serialNumber>
    <UDN>uuid:a4fa69b6-1461-fa59-cd1a-ae296239d279</UDN>
    <dlna:X_DLNACAP/>
    <dlna:X_DLNADOC>DMS-1.50</dlna:X_DLNADOC>
    <dlna:X_DLNADOC>M-DMS-1.50</dlna:X_DLNADOC>
    <sec:ProductCap>smi,DCM10,getMediaInfo.sec,getCaptionInfo.sec</sec:ProductCap>
    <sec:X_ProductCap>smi,DCM10,getMediaInfo.sec,getCaptionInfo.sec</sec:X_ProductCap>
    <iconList>
      <icon>
        <mimetype>image/png</mimetype>
        <width>48</width>
        <height>48</height>
        <depth>8</depth>
        <url>/static/rclone-48x48.png</url>
      </icon>
      <icon>
        <mimetype>image/png</mimetype>
        <width>120</width>
        <height>120</height>
        <depth>8</depth>
        <url>/static/rclone-120x120.png</url>
      </icon>
    </iconList>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>
        <SCPDURL>/static/ContentDirectory.xml</SCPDURL>
        <controlURL>/ctl</controlURL>
        <eventSubURL></eventSubURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
        <SCPDURL>/static/ConnectionManager.xml</SCPDURL>
        <controlURL>/ctl</controlURL>
        <eventSubURL></eventSubURL>
      </service>
      <service>
        <serviceType>urn:microsoft.com:service:X_MS_MediaReceiverRegistrar:1</serviceType>
        <serviceId>urn:microsoft.com:serviceId:X_MS_MediaReceiverRegistrar</serviceId>
        <SCPDURL>/static/X_MS_MediaReceiverRegistrar.xml</SCPDURL>
        <controlURL>/ctl</controlURL>
        <eventSubURL></eventSubURL>
      </service>
    </serviceList>
    <presentationURL>/</presentationURL>
  </device>
</root>
"""#

let rcloneBrowseRoot = #"""
<?xml version="1.0" encoding="utf-8" standalone="yes"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;&lt;container id=&quot;%2Fbig&quot; parentID=&quot;0&quot; restricted=&quot;1&quot; searchable=&quot;0&quot; childCount=&quot;1&quot;&gt;&lt;upnp:class&gt;object.container.storageFolder&lt;/upnp:class&gt;&lt;dc:title&gt;big&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;/container&gt;&lt;container id=&quot;%2FMovies&quot; parentID=&quot;0&quot; restricted=&quot;1&quot; searchable=&quot;0&quot; childCount=&quot;2&quot;&gt;&lt;upnp:class&gt;object.container.storageFolder&lt;/upnp:class&gt;&lt;dc:title&gt;Movies&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;/container&gt;&lt;container id=&quot;%2FOdd+Names&quot; parentID=&quot;0&quot; restricted=&quot;1&quot; searchable=&quot;0&quot; childCount=&quot;1&quot;&gt;&lt;upnp:class&gt;object.container.storageFolder&lt;/upnp:class&gt;&lt;dc:title&gt;Odd Names&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;/container&gt;&lt;container id=&quot;%2FShows&quot; parentID=&quot;0&quot; restricted=&quot;1&quot; searchable=&quot;0&quot; childCount=&quot;1&quot;&gt;&lt;upnp:class&gt;object.container.storageFolder&lt;/upnp:class&gt;&lt;dc:title&gt;Shows&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;/container&gt;&lt;/DIDL-Lite&gt;</Result>
<NumberReturned>4</NumberReturned>
<TotalMatches>4</TotalMatches>
<UpdateID>1658</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
"""#

let rcloneBrowseMovies = #"""
<?xml version="1.0" encoding="utf-8" standalone="yes"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;&lt;item id=&quot;%2FMovies%2FTest+Movie+%282020%29.mkv&quot; parentID=&quot;%2FMovies&quot; restricted=&quot;1&quot; searchable=&quot;0&quot;&gt;&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;&lt;dc:title&gt;Test Movie (2020)&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;res protocolInfo=&quot;http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000&quot; size=&quot;3145728&quot;&gt;http://127.0.0.1:17879/r/Movies/Test%20Movie%20%282020%29.mkv&lt;/res&gt;&lt;res protocolInfo=&quot;http-get:*:application/x-subrip:*&quot;&gt;http://127.0.0.1:17879/r/Movies/Test%20Movie%20%282020%29.en.srt&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</Result>
<NumberReturned>1</NumberReturned>
<TotalMatches>1</TotalMatches>
<UpdateID>1658</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
"""#

let rcloneBrowseShows = #"""
<?xml version="1.0" encoding="utf-8" standalone="yes"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;&lt;container id=&quot;%2FShows%2FTest+Show+%282019%29&quot; parentID=&quot;%2FShows&quot; restricted=&quot;1&quot; searchable=&quot;0&quot; childCount=&quot;1&quot;&gt;&lt;upnp:class&gt;object.container.storageFolder&lt;/upnp:class&gt;&lt;dc:title&gt;Test Show (2019)&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;/container&gt;&lt;/DIDL-Lite&gt;</Result>
<NumberReturned>1</NumberReturned>
<TotalMatches>1</TotalMatches>
<UpdateID>1658</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
"""#

let rcloneBrowseSeason1 = #"""
<?xml version="1.0" encoding="utf-8" standalone="yes"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;&lt;item id=&quot;%2FShows%2FTest+Show+%282019%29%2FSeason+1%2FTest+Show+-+S01E01+-+Pilot.mkv&quot; parentID=&quot;%2FShows%2FTest+Show+%282019%29%2FSeason+1&quot; restricted=&quot;1&quot; searchable=&quot;0&quot;&gt;&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;&lt;dc:title&gt;Test Show - S01E01 - Pilot&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;res protocolInfo=&quot;http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000&quot; size=&quot;1048576&quot;&gt;http://127.0.0.1:17879/r/Shows/Test%20Show%20%282019%29/Season%201/Test%20Show%20-%20S01E01%20-%20Pilot.mkv&lt;/res&gt;&lt;/item&gt;&lt;item id=&quot;%2FShows%2FTest+Show+%282019%29%2FSeason+1%2FTest+Show+-+S01E02.mkv&quot; parentID=&quot;%2FShows%2FTest+Show+%282019%29%2FSeason+1&quot; restricted=&quot;1&quot; searchable=&quot;0&quot;&gt;&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;&lt;dc:title&gt;Test Show - S01E02&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;res protocolInfo=&quot;http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000&quot; size=&quot;1048576&quot;&gt;http://127.0.0.1:17879/r/Shows/Test%20Show%20%282019%29/Season%201/Test%20Show%20-%20S01E02.mkv&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</Result>
<NumberReturned>2</NumberReturned>
<TotalMatches>2</TotalMatches>
<UpdateID>1658</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
"""#

let rcloneBrowseMissingFault = #"""
<?xml version="1.0" encoding="utf-8" standalone="yes"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><Fault xmlns="http://schemas.xmlsoap.org/soap/envelope/">
  <faultcode>http://schemas.xmlsoap.org/soap/envelope/:Client</faultcode>
  <faultstring>UPnPError</faultstring>
  <detail>
    <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
      <errorCode>701</errorCode>
      <errorDescription>file does not exist</errorDescription>
    </UPnPError>
  </detail>
</Fault></s:Body></s:Envelope>
"""#

let rcloneBrowseShow = #"""
<?xml version="1.0" encoding="utf-8" standalone="yes"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;&lt;container id=&quot;%2FShows%2FTest+Show+%282019%29%2FSeason+1&quot; parentID=&quot;%2FShows%2FTest+Show+%282019%29&quot; restricted=&quot;1&quot; searchable=&quot;0&quot; childCount=&quot;2&quot;&gt;&lt;upnp:class&gt;object.container.storageFolder&lt;/upnp:class&gt;&lt;dc:title&gt;Season 1&lt;/dc:title&gt;&lt;dc:date&gt;2026-11-16&lt;/dc:date&gt;&lt;/container&gt;&lt;/DIDL-Lite&gt;</Result>
<NumberReturned>1</NumberReturned>
<TotalMatches>1</TotalMatches>
<UpdateID>1658</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
"""#

