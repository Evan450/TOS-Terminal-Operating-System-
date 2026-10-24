local h=require("computer")local f=require("kernel.serialize")
local e={}e.VERSION=1;e.MAGIC="TOS"e.MAX_SIZE=8192
e.TYPE={PING="ping",PONG="pong",HELLO="hello",HELLO_ACK="hello_ack",INFO_REQ="info_req",INFO_RES="info_res",MSG="msg",MSG_ACK="msg_ack",FILE_REQ="file_req",FILE_RES="file_res",FILE_DENY="file_deny",TRUST_REQ="trust_req",TRUST_ACK="trust_ack",TRUST_DENY="trust_deny",TRUST_REVOKE="trust_rev",CHALLENGE="challenge",CHALLENGE_RES="chall_res",REMOTE_EXEC="remote_exec",REMOTE_RES="remote_res",CLUSTER_REGISTER="cl_reg",CLUSTER_REGISTER_ACK="cl_reg_ack",CLUSTER_HEARTBEAT="cl_hb",CLUSTER_ASSIGN="cl_asn",CLUSTER_ASSIGN_ACK="cl_asn_ack",CLUSTER_RESULT="cl_res",CLUSTER_RESULT_CHUNK="cl_res_chunk",CLUSTER_CANCEL="cl_cancel",CLUSTER_DRAIN="cl_drain",CLUSTER_STATUS_REQ="cl_st_req",CLUSTER_STATUS_RES="cl_st_res",CLUSTER_PAIR_INIT="cl_pair_init",CLUSTER_PAIR_CONFIRM="cl_pair_conf",CHAT_PAIR_INIT="ch_pair_init",CHAT_PAIR_CONFIRM="ch_pair_conf",MESH="mesh",MESH_ACK="mesh_ack",RELAY_FORWARD="rly_fwd",RELAY_FAIL="rly_fail",PEER_STATUS="peer_st",STORE_PUT="st_put",STORE_PUT_ACK="st_put_ack",STORE_PUT_CHUNK="st_put_chunk",STORE_LEASE_EXTEND="st_ext",STORE_RELEASE="st_rel",STORE_LIST="st_list",STORE_LIST_RES="st_list_res",STORE_ERROR="st_err",NETFS_REQ="nfs_req",NETFS_RES="nfs_res",DENY="deny",ERROR="error"}local g={}for b,a in pairs(e.TYPE)do g[a]=true end
function e.makePacket(b,c,a)a=a or{}
return
{magic=e.MAGIC,ver=e.VERSION,type=b,from=nil,to=
a.to or nil,seq=a.seq or math.random(0,0xFFFF),time=math.floor(h.uptime()*100),enc=
a.encrypted or false,payload=c or{}}end;function e.serialize(a)return f.compact(a)end
e.MAX_DECODE_COST=48*1024;e.MAX_DECODE_KEYS=256
function e.deserialize(a)
if not a or#a<10 then return nil,"Too short"end;if#a>e.MAX_SIZE then return nil,"Too large"end
local b,d=f.decode(a,{maxBytes=e.MAX_SIZE,maxCost=e.MAX_DECODE_COST,maxKeys=e.MAX_DECODE_KEYS})if not b then return nil,d end
if type(b)~="table"then return nil,"Not a table"end
local function c(i,j)if j>=8 then return false end
if type(i)=="table"then for l,k in pairs(i)do
if not c(k,j+1)then return false end end end;return true end;if not c(b,0)then return nil,"Table nesting too deep"end;return b end
function e.validate(a)if type(a)~="table"then return false,"Not a table"end;if
a.magic~=e.MAGIC then return false,"Not a TOS packet"end;if
not a.type then return false,"No message type"end
if not g[a.type]then return false,
"Unknown message type: "..tostring(a.type)end
if a.ver~=nil then if type(a.ver)~="number"then
return false,"Invalid protocol version field"end;if a.ver>e.VERSION then
return false,"Unsupported protocol version"end end;return true end
function e.ping()return e.makePacket(e.TYPE.PING,{})end
function e.pong()return e.makePacket(e.TYPE.PONG,{tos=true})end;function e.hello(a,b,c)
return e.makePacket(e.TYPE.HELLO,{hostname=a,version=b,dhPub=c})end
function e.helloAck(a,b,c)return
e.makePacket(e.TYPE.HELLO_ACK,{hostname=a,version=b,dhPub=c})end;function e.deny(a)return
e.makePacket(e.TYPE.DENY,{reason=a or"Access denied"})end;function e.error(a)
return e.makePacket(e.TYPE.ERROR,{message=
a or"Unknown error"})end;function e.message(a,b)return
e.makePacket(e.TYPE.MSG,{text=a},{encrypted=b})end;function e.challenge(a)return
e.makePacket(e.TYPE.CHALLENGE,{nonce=a})end
function e.challengeResponse(a,b)return
e.makePacket(e.TYPE.CHALLENGE_RES,{nonce=a,proof=b})end;function e.trustRequest(a)
return e.makePacket(e.TYPE.TRUST_REQ,{hostname=a})end;return e