"""Throwaway SMB server for the integration tests (impacket). Loopback only.

    python vp_smbserver.py <folder to share> [port]

Shares the folder as "Media" (impacket shows it as MEDIA); user tester / password testpass-local
(test values, not secrets). The tests only read.

One fix for impacket so that it answers like Samba/Windows do:
  * A failed login must be answered with a proper SMB2 ERROR body. impacket sends a session-setup body
    instead, and libsmb2 then waits for bytes that never come (a 40 second timeout instead of an error).

Known impacket difference left as it is: asking for the attributes of a file that does not exist gives
"access denied" instead of "not found" (SourceSMB checks the parent folder to tell the two apart).
"""
import sys
from impacket import smbserver
from impacket import smb3structs as smb2
from impacket.nt_errors import STATUS_LOGON_FAILURE
from impacket.ntlm import compute_nthash

_original_session_setup = smbserver.SMB2Commands.smb2SessionSetup


def _session_setup(connId, smbServer, recvPacket):
    commands, packet, status = _original_session_setup(connId, smbServer, recvPacket)
    if status == STATUS_LOGON_FAILURE:
        return [smb2.SMB2Error()], packet, status
    return commands, packet, status


smbserver.SMB2Commands.smb2SessionSetup = staticmethod(_session_setup)

folder = sys.argv[1]
port = int(sys.argv[2]) if len(sys.argv) > 2 else 12445

server = smbserver.SimpleSMBServer(listenAddress="127.0.0.1", listenPort=port)
server.addShare("Media", folder, "test media", readOnly="no")
server.setSMB2Support(True)
server.addCredential("tester", 1000, "", compute_nthash("testpass-local").hex())
server.setLogFile("")
server.start()
