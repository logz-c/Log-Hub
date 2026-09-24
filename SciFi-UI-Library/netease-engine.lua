--[[
    网易云音乐 for Roblox  v3.2  (重构版 / Rebuilt)
    ==================================================================
    v3.2 变更
    ------------------------------------------------------------------
    · 引擎化：始终把内部模块打包导出到 getgenv().NCM，外部 UI 可直接驱动
      （Search / Play / Toggle / Next / Prev / Seek / SetVolume / SetQueue /
        GetState / LyricAt …），不用碰内部字段名。
    · Headless 模式：加载前设 getgenv().NCM_OPTIONS = { Headless = true }，
      只启动引擎、不构建自带 UI —— 交给 uilib 的 MUSIC 分支显示。
    · Player 新增 getState() / setQueue() / playAt() / lyricAt()。
    · 修复（v3.1）：Login.loadCookie() 以前只 return 不写回 Net.cookie，
      且只在「登录」页里调用 → 启动后永远未登录，VIP 歌取不到直链，
      表现为「播放功能坏了」。现在函数内写回 + 在 main() 之前启动即调用。

    v3.0 变更
    ------------------------------------------------------------------
    1. 彻底重做 UI。旧版把 2700 行代码全塞进一个函数 __NCM_Main()，
       Luau 单函数局部变量上限 200，直接编译失败
       ("Out of local registers ... exceeded limit 200")，脚本根本跑不起来。
       本版按功能拆成多个小函数/模块，彻底解决该问题。
    2. 修掉旧版 "Fire is not a valid member of RBXScriptSignal" 崩溃
       （旧代码对一个事件调用了不存在的 :Fire()，现改为直接调用处理函数）。
    3. 验证码登录可用了。旧版短信/验证码登录依赖第三方 Worker
       (ncm-api.meisdad321.workers.dev) 做 WEAPI 加密，该 Worker 已下线，
       所以一登录就失败。
       本版把 WEAPI 加解密完整写进脚本（纯 Luau 实现 AES-128-CBC + RSA），
       不再依赖任何第三方服务：
         · 短信验证码登录：填手机号 -> 发验证码 -> 填验证码 -> 自动登录
           （登录成功后自动抓取 Cookie，不用再手动去浏览器复制）
         · Cookie 登录：保留，作为最稳的兜底方式
    4. 「我喜欢的音乐」现在能显示云端红心歌单（旧版只有本地收藏），
       登录后可拉取账号真实的红心列表。
    5. 直连 music.163.com 官方接口，Cookie 只作为请求头发送，不外泄。
    ------------------------------------------------------------------
    免责声明：仅供个人技术学习交流，禁止商业使用。音乐版权归网易云音乐及
    各权利人所有。登录功能调用官方接口，请自行评估账号风险，建议用小号。
    ==================================================================
]]

-- ══════════════════════════════════════════════════════════════════
-- 基础服务与执行器能力探测
-- ══════════════════════════════════════════════════════════════════
local HttpService  = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local LP           = game:GetService("Players").LocalPlayer
local PlayerGui    = LP:WaitForChild("PlayerGui")

local function _get(name)
    local ok, v = pcall(function() return getfenv()[name] end)
    if ok and v ~= nil then return v end
    local ok2, v2 = pcall(function() return _G[name] end)
    if ok2 and v2 ~= nil then return v2 end
    return nil
end

local rawRequest = (type(_G.syn) == "table" and _G.syn.request) or _get("request") or _get("http_request") or _get("httprequest")
local fnWrite  = _get("writefile")
local fnRead   = _get("readfile")
local fnIsFile = _get("isfile")
local fnIsFold = _get("isfolder")
local fnMkDir  = _get("makefolder")
local fnAsset  = _get("getcustomasset") or _get("getsynasset")

local taskLib = task or {
    spawn = function(f, ...) return (spawn or coroutine.wrap)(f, ...) end,
    wait  = function(t) return (wait or function() end)(t) end,
    delay = function(t, f) return (delay or spawn)(t, f) end,
}

-- ── v3.2 运行选项 ─────────────────────────────────────────────────
-- 加载前设置 getgenv().NCM_OPTIONS = { Headless = true } 可以只启动引擎、不建自带 UI，
-- 交给外部界面（例如 uilib 的 MUSIC 分支）来驱动。引擎始终导出到 getgenv().NCM。
local OPTS = {}
pcall(function()
    local g = (getgenv and getgenv()) or _G
    if type(g.NCM_OPTIONS) == "table" then OPTS = g.NCM_OPTIONS end
end)
local HEADLESS = OPTS.Headless == true

local CFG = {
    Api      = "https://music.163.com",
    CookieF  = "NetMusicCfg/cookie.json",
    FavF     = "NetMusicCfg/favorites.json",
    UA       = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    Ref      = "https://music.163.com/",
}

local function ensureDir(d)
    pcall(function() if fnIsFold and not fnIsFold(d) then fnMkDir(d) end end)
end
ensureDir("NetMusicCfg")
ensureDir("NetMusicTemp")

-- ══════════════════════════════════════════════════════════════════
-- Weapi：网易云 WEAPI 加密（纯 Luau，不依赖任何第三方）
--   算法：params = AES(Base64(AES(json, NONCE)), secKey)
--         encSecKey = RSA(secKey) mod 固定 modulus
--   已用 Node 对照验证：AES 与 crypto 模块一致、RSA 与 BigInt 一致，
--   并已实测拿到真实 unikey（code 200）。
-- ══════════════════════════════════════════════════════════════════
local Weapi = {}
Weapi.NONCE   = "0CoJUm6Qyw8W8jud"
Weapi.MODULUS = "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b72515"
             .. "2b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda"
             .. "92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe48"
             .. "75d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7"
Weapi.IV      = "0102030405060708"
Weapi.BASE    = 65536

-- AES S-box（标准表，硬编码避免仿射变换算错）
local SBOX_HEX =
      "637c777bf26b6fc53001672bfed7ab76"
   .. "ca82c97dfa5947f0add4a2af9ca472c0"
   .. "b7fd9326363ff7cc34a5e5f171d83115"
   .. "04c723c31896059a071280e2eb27b275"
   .. "09832c1a1b6e5aa0523bd6b329e32f84"
   .. "53d100ed20fcb15b6acbbe394a4c58cf"
   .. "d0efaafb434d338545f9027f503c9fa8"
   .. "51a3408f929d38f5bcb6da2110fff3d2"
   .. "cd0c13ec5f974417c4a77e3d645d1973"
   .. "60814fdc222a908846eeb814de5e0bdb"
   .. "e0323a0a4906245cc2d3ac629195e479"
   .. "e7c8376d8dd54ea96c56f4ea657aae08"
   .. "ba78252e1ca6b4c6e8dd741f4bbd8b8a"
   .. "703eb5664803f60e613557b986c11d9e"
   .. "e1f8981169d98e949b1e87e9ce5528df"
   .. "8ca1890dbfe6426841992d0fb054bb16"

local SBOX = {}
do
    for i = 0, 255 do
        SBOX[i] = tonumber(string.sub(SBOX_HEX, i * 2 + 1, i * 2 + 2), 16) or 0
    end
end
local RCON = {0, 1, 2, 4, 8, 16, 32, 64, 128, 27, 54}

-- 本执行器的 Luau 解析器不接受 & | ~ << >> 这些位运算符
-- （实测 `return 5 & 3` 直接报 syntax error），所以统一用 bit32。
local band   = bit32.band
local bor    = bit32.bor
local bxor   = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift

function Weapi.bytes(s)
    local o = {}
    for i = 1, #s do o[i] = band(string.byte(s, i), 0xff) end
    return o
end

local B64C = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function Weapi.b64(b)
    local out = {}
    local i = 1
    while i <= #b do
        local b0, b1, b2 = b[i], b[i + 1], b[i + 2]
        local n = bor(lshift(b0, 16), lshift((b1 or 0), 8), (b2 or 0))
        local c1 = band(rshift(n, 18), 63) + 1
        local c2 = band(rshift(n, 12), 63) + 1
        local c3 = band(rshift(n, 6), 63) + 1
        local c4 = band(n, 63) + 1
        out[#out + 1] = string.sub(B64C, c1, c1)
        out[#out + 1] = string.sub(B64C, c2, c2)
        out[#out + 1] = (b1 == nil) and "=" or string.sub(B64C, c3, c3)
        out[#out + 1] = (b2 == nil) and "=" or string.sub(B64C, c4, c4)
        i = i + 3
    end
    return table.concat(out)
end

-- GF(2^8) 乘法
local function gfMul(a, b)
    local p = 0
    for _ = 1, 8 do
        if band(b, 1) ~= 0 then p = bxor(p, a) end
        b = rshift(b, 1)
        if band(a, 0x80) ~= 0 then
            a = band(bxor(lshift(a, 1), 0x1b), 0xff)
        else
            a = band(lshift(a, 1), 0xff)
        end
    end
    return band(p, 0xff)
end

function Weapi.keyExpansion(key)
    local w = {}
    for i = 1, 16 do w[i] = key[i] end
    local i = 17
    while i <= 176 do
        local t0, t1, t2, t3 = w[i - 4], w[i - 3], w[i - 2], w[i - 1]
        if ((i - 1) % 16) == 0 then
            local r0, r1, r2, r3 = t1, t2, t3, t0          -- RotWord
            t0, t1, t2, t3 = SBOX[r0], SBOX[r1], SBOX[r2], SBOX[r3]  -- SubWord
            t0 = bxor(t0, RCON[((i - 1) / 16) + 1])
        end
        w[i]     = bxor(w[i - 16], t0)
        w[i + 1] = bxor(w[i - 15], t1)
        w[i + 2] = bxor(w[i - 14], t2)
        w[i + 3] = bxor(w[i - 13], t3)
        i = i + 4
    end
    return w
end

function Weapi.encryptBlock(block, rk)
    local s = {}
    for i = 1, 16 do s[i] = bxor(block[i], rk[i]) end
    local SH = {1, 6, 11, 16, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12} -- 1-based ShiftRows
    for r = 1, 10 do
        for i = 1, 16 do s[i] = SBOX[s[i]] end
        local ns = {}
        for i = 1, 16 do ns[i] = s[SH[i]] end
        if r < 10 then
            for c = 0, 3 do
                local i  = c * 4 + 1
                local a0, a1, a2, a3 = ns[i], ns[i + 1], ns[i + 2], ns[i + 3]
                s[i]     = bxor(bxor(bxor(gfMul(a0, 2), gfMul(a1, 3)), a2), a3)
                s[i + 1] = bxor(bxor(bxor(a0, gfMul(a1, 2)), gfMul(a2, 3)), a3)
                s[i + 2] = bxor(bxor(bxor(a0, a1), gfMul(a2, 2)), gfMul(a3, 3))
                s[i + 3] = bxor(bxor(bxor(gfMul(a0, 3), a1), a2), gfMul(a3, 2))
            end
        else
            for i = 1, 16 do s[i] = ns[i] end
        end
        for i = 1, 16 do s[i] = bxor(s[i], rk[r * 16 + i]) end
    end
    return s
end

function Weapi.aesCbc(plain, key, iv)
    local padded = {}
    for i = 1, #plain do padded[i] = plain[i] end
    local pad = 16 - (#plain % 16)
    for _ = 1, pad do padded[#padded + 1] = pad end
    local rk = Weapi.keyExpansion(key)
    local prev, out = {}, {}
    for i = 1, 16 do prev[i] = iv[i] end
    local off = 1
    while off <= #padded do
        local blk = {}
        for i = 1, 16 do blk[i] = bxor(padded[off + i - 1], prev[i]) end
        local enc = Weapi.encryptBlock(blk, rk)
        for i = 1, 16 do out[#out + 1] = enc[i]; prev[i] = enc[i] end
        off = off + 16
    end
    return out
end

function Weapi.aesB64(text, key)
    return Weapi.b64(Weapi.aesCbc(Weapi.bytes(text), Weapi.bytes(key), Weapi.bytes(Weapi.IV)))
end

-- ── RSA / encSecKey ───────────────────────────────────────────
-- WEAPI 的 encSecKey = RSA(secKey)，secKey 是每次随机生成的 16 字节会话密钥。
-- 但 secKey 只是会话密钥：服务端用私钥解出 secKey，再用它解 params。
-- 所以 secKey 可以是固定常量，encSecKey 离线算一次写死即可 —— 不必在
-- Roblox 里实现大数运算和 RSA。
-- 实测（Node 直连 music.163.com，两个不同 payload 复用同一组固定密钥）：
--   /weapi/login/qrcode/unikey      -> {"code":200,"unikey":"..."}
--   /weapi/cellphone/existence/check-> {"exist":1,...}
-- 均返回 200，方案成立。
Weapi.SECKEY = "0123456789abcdef"
Weapi.ENC    = "35701388baf89fed412e11269b9c76625d095ecaf17f03fa018abe19ea2d38b9"
           .. "49debf242ee39a71ca1f6cda71b1b86a45aa909ee27f7e78e267d34e732f0de9"
           .. "48206c3340a788d0003372183e2f753c1f78b66ac23d134ac1fc9b993156520e"
           .. "a826b8aa89a962d4491b4b8d7e08738e1da9b07aa39bf4a7ef0b1c210728cd52"

-- 生成 WEAPI 请求体：返回 params 与 encSecKey
function Weapi.build(obj)
    local text = HttpService:JSONEncode(obj)
    return Weapi.aesB64(Weapi.aesB64(text, Weapi.NONCE), Weapi.SECKEY), Weapi.ENC
end

-- ══════════════════════════════════════════════════════════════════
-- Net：网络层（Cookie 清洗 / 请求 / 取 Set-Cookie）
-- ══════════════════════════════════════════════════════════════════
local Net = { cookie = "" }

-- Roblox request() 禁止请求头出现 CR/LF/TAB；浏览器复制来的 Cookie 常带换行，
-- 一旦带上会导致所有需要登录的请求静默失败（表现：登录了却显示未登录）。
function Net.normalize(c)
    if type(c) ~= "string" then return "" end
    local s = c:gsub("[\r\n\t]+", " ")
    s = s:gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Net.headers(extra)
    local h = { ["User-Agent"] = CFG.UA, ["Referer"] = CFG.Ref, ["Accept"] = "*/*" }
    local ck = Net.normalize(Net.cookie)
    if ck ~= "" then h["Cookie"] = ck end
    if extra then for k, v in pairs(extra) do h[k] = v end end
    return h
end

function Net.fetch(url, method, body, extra)
    if rawRequest then
        local ok, res = pcall(function()
            return rawRequest({ Url = url, Method = method or "GET", Headers = Net.headers(extra), Body = body })
        end)
        if ok and res and res.Body and res.Body ~= "" then
            return res.Body, res.Headers
        end
    end
    if (method or "GET") == "GET" then
        local ok, r = pcall(function() return game:HttpGet(url, true) end)
        if ok and r and r ~= "" then return r, nil end
    end
    return nil, nil
end

function Net.post(url, params, encSecKey)
    local body = "params=" .. Weapi.urlEncode(params) .. "&encSecKey=" .. encSecKey
    return Net.fetch(url, "POST", body, { ["Content-Type"] = "application/x-www-form-urlencoded" })
end

function Weapi.urlEncode(s)
    return tostring(s or ""):gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", string.byte(c)) end)
end

-- 从响应头里抓 Set-Cookie，拼成可用的 Cookie 串（验证码登录自动登录用）
function Net.grabCookie(headers)
    if type(headers) ~= "table" then return nil end
    local found = {}
    for k, v in pairs(headers) do
        if tostring(k):lower():find("set-cookie", 1, true) then
            if type(v) == "table" then
                for _, s in ipairs(v) do found[#found + 1] = tostring(s) end
            else
                found[#found + 1] = tostring(v)
            end
        end
    end
    if #found == 0 then return nil end
    local pairs_ = {}
    for _, line in ipairs(found) do
        local first = line:match("^([^;]+)")
        if first then
            local k, val = first:match("^%s*([^=]+)=(.*)$")
            if k then pairs_[k:gsub("^%s+", ""):gsub("%s+$", "")] = (val or ""):gsub("^%s+", ""):gsub("%s+$", "") end
        end
    end
    local out = {}
    for k, v in pairs(pairs_) do out[#out + 1] = k .. "=" .. v end
    if #out == 0 then return nil end
    return table.concat(out, "; ")
end

-- ══════════════════════════════════════════════════════════════════
-- Api：接口封装（全部直连 music.163.com）
-- ══════════════════════════════════════════════════════════════════
local Api = {}

local function jsonDecode(s)
    local ok, r = pcall(function() return HttpService:JSONDecode(s) end)
    if ok then return r end
    return nil
end
local function urlEncode(s)
    return tostring(s or ""):gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", string.byte(c)) end)
end

-- 注意：搜索必须用 /api/search/get，不能用 /api/search/get/web。
-- 后者从 Roblox 通道请求时会返回 eapi 加密体（{"result":"<hex>"}），解不开。
function Api.search(kw, limit)
    local body = Net.fetch(CFG.Api .. "/api/search/get?s=" .. urlEncode(kw) .. "&type=1&offset=0&limit=" .. tostring(limit or 30), "GET")
    local d = jsonDecode(body or "")
    if not d or not d.result or not d.result.songs then return {} end
    local out = {}
    for _, s in ipairs(d.result.songs) do
        local n = {}
        for _, a in ipairs(s.artists or {}) do n[#n + 1] = a.name or "" end
        out[#out + 1] = {
            id = tostring(s.id), name = s.name or "未知",
            artist = table.concat(n, " / "), dur = (s.duration or 0) / 1000,
            fee = s.fee or 0,
            artistId = (s.artists and s.artists[1] and tostring(s.artists[1].id)) or "",
        }
    end
    return out
end

function Api.url(id)
    local body = Net.fetch(CFG.Api .. "/api/song/enhance/player/url/v1?ids=%5B" .. tostring(id) .. "%5D&level=standard&encodeType=mp3", "GET")
    local d = jsonDecode(body or "")
    if d and d.data and d.data[1] and d.data[1].url then return d.data[1] end
    return nil
end

function Api.lyric(id)
    local body = Net.fetch(CFG.Api .. "/api/song/lyric?id=" .. tostring(id) .. "&lv=-1&kv=-1&tv=-1", "GET")
    local d = jsonDecode(body or "")
    if not d then return nil end
    return d.lrc and d.lrc.lyric or nil, (d.tlyric and d.tlyric.lyric) or nil
end

function Api.account()
    local body = Net.fetch(CFG.Api .. "/api/nuser/account/get", "GET")
    local d = jsonDecode(body or "")
    if not d or not d.profile then return nil end
    local vt = tonumber(d.profile.vipType) or 0
    local vn = "普通用户"
    if vt >= 11 then vn = "黑胶VIP" elseif vt > 0 then vn = "VIP" end
    return {
        ok = true, isVip = vt > 0, nickname = tostring(d.profile.nickname or ""),
        vipName = vn, userId = tostring(d.profile.userId or ""),
        avatar = tostring(d.profile.avatarUrl or ""),
    }
end

-- 云端「我喜欢的音乐」：先取红心 id 列表，再分批取详情
local Liked = { userId = nil, cache = nil }
function Liked.setUser(uid) if uid and tostring(uid) ~= "" then Liked.userId = tostring(uid) end end
function Liked.clear() Liked.cache = nil end
function Liked.songs(force)
    if not Liked.userId then return {}, "未登录" end
    if Liked.cache and not force then return Liked.cache, nil end
    local body = Net.fetch(CFG.Api .. "/api/song/like/get?uid=" .. Liked.userId, "GET")
    local d = jsonDecode(body or "")
    if not d or not d.ids then return {}, "取红心列表失败" end
    if #d.ids == 0 then Liked.cache = {}; return Liked.cache, nil end
    local songs, i = {}, 1
    while i <= #d.ids do
        local chunk = {}
        for j = i, math.min(i + 99, #d.ids) do chunk[#chunk + 1] = tostring(d.ids[j]) end
        local b2 = Net.fetch(CFG.Api .. "/api/song/detail?ids=" .. urlEncode("[" .. table.concat(chunk, ",") .. "]"), "GET")
        local det = jsonDecode(b2 or "")
        if det and det.songs then
            for _, s in ipairs(det.songs) do
                local n = {}
                for _, a in ipairs(s.artists or {}) do n[#n + 1] = a.name or "" end
                songs[#songs + 1] = {
                    id = tostring(s.id), name = s.name or "未知",
                    artist = table.concat(n, " / "), dur = (s.duration or 0) / 1000,
                    fee = s.fee or 0,
                    artistId = (s.artists and s.artists[1] and tostring(s.artists[1].id)) or "",
                }
            end
        end
        i = i + 100
        if i <= #d.ids then taskLib.wait(0.15) end
    end
    Liked.cache = songs
    return songs, nil
end
Api.Liked = Liked

-- ══════════════════════════════════════════════════════════════════
-- Login：Cookie 登录 + 短信验证码登录（WEAPI 本地实现）
-- ══════════════════════════════════════════════════════════════════
local Login = {}

function Login.saveCookie(c)
    Net.cookie = Net.normalize(c)
    pcall(function() if fnWrite then fnWrite(CFG.CookieF, Net.cookie) end end)
end
function Login.loadCookie()
    if not (fnRead and fnIsFile) then return "" end
    local ok = pcall(fnIsFile, CFG.CookieF)
    if not ok then return "" end
    local ok2, c = pcall(fnRead, CFG.CookieF)
    if ok2 and type(c) == "string" and c ~= "" then
        -- ★ 必须写回内存：只 return 的话调用方拿到字符串但 Net.cookie 仍为空，
        -- 所有请求都变成未登录状态，VIP 歌取不到直链（表现为「播放功能坏了」）。
        Net.cookie = Net.normalize(c)
        return Net.cookie
    end
    return ""
end

-- Cookie 登录：写入后直接查账号接口验证
function Login.byCookie(c)
    Login.saveCookie(c)
    local acc = Api.account()
    if acc then
        Liked.setUser(acc.userId)
        return true, acc
    end
    return false, nil
end

-- 短信验证码登录 第1步：发送验证码
function Login.smsSend(phone, ctcode)
    local params, enc = Weapi.build({ cellphone = tostring(phone), ctcode = tostring(ctcode or "86") })
    local body, headers = Net.post(CFG.Api .. "/weapi/sms/captcha/sent", params, enc)
    local ck = Net.grabCookie(headers)
    if ck and ck ~= "" then Net.cookie = Net.normalize((Net.cookie ~= "" and (Net.cookie .. "; ") or "") .. ck) end
    local d = jsonDecode(body or "")
    if not d then return false, "发送失败（无响应）" end
    if d.code == 200 then return true, "验证码已发送" end
    return false, ("发送失败 code=" .. tostring(d.code) .. " " .. tostring(d.message or ""))
end

-- 短信验证码登录 第2步：校验验证码并完成登录
function Login.smsVerify(phone, code, ctcode)
    local params, enc = Weapi.build({
        cellphone = tostring(phone), captcha = tostring(code),
        ctcode = tostring(ctcode or "86"),
    })
    local body, headers = Net.post(CFG.Api .. "/weapi/sms/captcha/verify", params, enc)
    local d = jsonDecode(body or "")
    local ck = Net.grabCookie(headers)
    if ck and ck ~= "" then
        Net.cookie = Net.normalize((Net.cookie ~= "" and (Net.cookie .. "; ") or "") .. ck)
    end
    -- 校验接口有时只返回成功标志，需要再用 cellphone 登录接口换正式登录态
    if not (d and d.code == 200) then
        return false, ("验证码错误 code=" .. tostring(d and d.code) .. " " .. tostring(d and d.message or ""))
    end
    local p2, e2 = Weapi.build({
        phone = tostring(phone), countrycode = tostring(ctcode or "86"),
        captcha = tostring(code), rememberLogin = "true",
    })
    local b2, h2 = Net.post(CFG.Api .. "/weapi/login/cellphone", p2, e2)
    local ck2 = Net.grabCookie(h2)
    if ck2 and ck2 ~= "" then
        Net.cookie = Net.normalize((Net.cookie ~= "" and (Net.cookie .. "; ") or "") .. ck2)
    end
    local acc = Api.account()
    if acc then
        Login.saveCookie(Net.cookie)
        Liked.setUser(acc.userId)
        return true, acc
    end
    return false, "已验证但未能获取账号信息，请改用 Cookie 登录"
end

-- ══════════════════════════════════════════════════════════════════
-- 持久化（本地收藏）
-- ══════════════════════════════════════════════════════════════════
local Fav = { list = {} }
function Fav.load()
    if not (fnRead and fnIsFile and fnIsFile(CFG.FavF)) then return end
    local ok, s = pcall(fnRead, CFG.FavF)
    if ok and type(s) == "string" and s ~= "" then
        local d = jsonDecode(s)
        if type(d) == "table" then Fav.list = d end
    end
end
function Fav.save()
    pcall(function() if fnWrite then fnWrite(CFG.FavF, HttpService:JSONEncode(Fav.list)) end end)
end
function Fav.has(id)
    for _, v in ipairs(Fav.list) do if tostring(v.id) == tostring(id) then return true end end
    return false
end
function Fav.toggle(song)
    if Fav.has(song.id) then
        local t = {}
        for _, v in ipairs(Fav.list) do if tostring(v.id) ~= tostring(song.id) then t[#t + 1] = v end end
        Fav.list = t
        Fav.save(); return false
    end
    Fav.list[#Fav.list + 1] = song
    Fav.save(); return true
end

-- ══════════════════════════════════════════════════════════════════
-- 播放控制
-- ══════════════════════════════════════════════════════════════════
local Player = { sound = nil, index = 0, queue = {}, lyric = nil, lyricTr = nil, onUpdate = nil }

local function ensureSound()
    if Player.sound and Player.sound.Parent then return Player.sound end
    local s = Instance.new("Sound")
    s.Name = "NCM_Sound"
    s.Volume = 0.6
    s.Parent = PlayerGui
    Player.sound = s
    return s
end

-- 每首歌必须用「独立文件名」：getcustomasset 是按文件路径缓存资源的，
-- 如果所有歌都写同一个 song.mp3，切歌时 fnAsset 返回的还是第一首的 asset id，
-- SoundId 实际没变 —— 表现就是「点了新歌却还在放旧的 / 干脆不出声」。
local function songPath(songId)
    return "NetMusicTemp/song_" .. tostring(songId) .. ".mp3"
end

local function playUrl(url, songId)
    local s = ensureSound()
    if fnAsset and fnWrite then
        local ok, b = pcall(function()
            local p = songPath(songId)
            local need = true
            if fnIsFile then
                local okf, ex = pcall(fnIsFile, p)
                if okf and ex then need = false end   -- 已缓存，直接复用
            end
            if need then
                local body = Net.fetch(url, "GET")
                if not body or #body < 1024 then return nil end
                fnWrite(p, body)
            end
            return fnAsset(p)
        end)
        if ok and b then
            s:Stop()                 -- 先停：正在播放时直接换 SoundId 再 Play 常常不生效
            s.SoundId = b
            local t0 = tick()
            while (not s.IsLoaded) and ((tick() - t0) < 5) do taskLib.wait(0.05) end
            s.TimePosition = 0
            s:Play()
            return true, nil
        end
    end
    -- 兜底：没有 getcustomasset 时直接把直链塞给 SoundId（多数执行器不支持）
    s:Stop()
    s.SoundId = url
    local okPlay = pcall(function() s:Play() end)
    if okPlay then return true, nil end
    return false, "播放失败"
end

Player.onStatus = nil
Player.gen = 0
local function setStatus(t)
    Player.status = t
    if Player.onStatus then Player.onStatus(t) end
end

-- 取直链 -> 下载 -> 播放 -> 拉歌词。整体异步，避免点击后 UI 卡住。
local function loadAndPlay(song, myGen)
    setStatus("获取直链…")
    local d = Api.url(song.id)
    if Player.gen ~= myGen then return end     -- 期间又切歌了，丢弃这次结果
    if not d or not d.url then
        setStatus("无版权 / 需 VIP / 取直链失败")
        return
    end
    setStatus("缓冲中…")
    local ok, err = playUrl(d.url, song.id)
    if Player.gen ~= myGen then return end
    if not ok then setStatus(tostring(err)) return end

    Player.current = song
    Player.autoNexted = false
    setStatus(nil)

    Player.lyric, Player.lyricTr = Api.lyric(song.id)
    Player.lyricLines = nil
    if Player.lyric then
        local lines = {}
        for line in tostring(Player.lyric):gmatch("[^\r\n]+") do
            local m, sec, txt = line:match("^%[(%d+):(%d+[%.%d]*)%]%s*(.*)$")
            if m and sec then lines[#lines + 1] = { t = tonumber(m) * 60 + tonumber(sec), text = (txt ~= "" and txt) or "..." } end
        end
        table.sort(lines, function(a, b) return a.t < b.t end)
        Player.lyricLines = lines
    end
    if Player.onUpdate then Player.onUpdate() end
end

function Player.play(song)
    if not song then return false, "无歌曲" end
    -- 立刻建好 Sound 并停掉旧音轨：既保证 Player.sound 从一开始就不为 nil
    -- （外部随时可读音量/进度），也让切歌马上静音，不用等新歌下载完。
    ensureSound():Stop()
    Player.gen = (Player.gen or 0) + 1
    local myGen = Player.gen
    Player.current = song
    Player.lyricLines = nil
    Player.autoNexted = false
    if Player.onUpdate then Player.onUpdate() end
    taskLib.spawn(function() loadAndPlay(song, myGen) end)
    return true, nil
end

function Player.toggle()
    local s = ensureSound()
    if s.IsPlaying then s:Pause() else pcall(function() s:Resume() end) end
    if Player.onUpdate then Player.onUpdate() end
end
function Player.setVolume(v) ensureSound().Volume = math.clamp(v or 0.6, 0, 1) end
function Player.seek(pos)
    local s = ensureSound()
    pcall(function() s.TimePosition = math.clamp(pos or 0, 0, math.max(0, s.TimeLength)) end)
end
function Player.next_()
    if #Player.queue == 0 then return end
    Player.index = (Player.index % #Player.queue) + 1
    Player.play(Player.queue[Player.index])
end
function Player.prev_()
    if #Player.queue == 0 then return end
    Player.index = ((Player.index - 2) % #Player.queue) + 1
    Player.play(Player.queue[Player.index])
end

-- ── v3.2：给外部界面（uilib MUSIC 分支等）用的查询/驱动接口 ──────
-- 外部 UI 不需要知道内部字段名，只轮询 getState() 即可。
function Player.setQueue(list, startIndex)
    Player.queue = list or {}
    Player.index = math.max(1, math.min(startIndex or 1, math.max(1, #Player.queue)))
    return #Player.queue
end

function Player.playAt(i)
    if #Player.queue == 0 then return false end
    i = math.max(1, math.min(i or 1, #Player.queue))
    Player.index = i
    return Player.play(Player.queue[i])
end

function Player.getState()
    local s = ensureSound()
    return {
        playing = s.IsPlaying,
        loaded  = s.IsLoaded,
        pos     = s.TimePosition or 0,
        len     = s.TimeLength or 0,
        volume  = s.Volume,
        song    = Player.current,
        status  = Player.status,
        index   = Player.index,
        count   = #Player.queue,
        queue   = Player.queue,
    }
end

-- 当前进度对应的歌词行（没歌词返回 nil）
function Player.lyricAt(pos)
    local lines = Player.lyricLines
    if not lines or #lines == 0 then return nil, nil end
    local cur, idx = nil, 0
    for i, l in ipairs(lines) do
        if l.t <= (pos or 0) then cur = l.text; idx = i else break end
    end
    return cur, idx
end

-- ══════════════════════════════════════════════════════════════════
-- UI（自制的简洁深色界面；按功能拆函数，避免单函数局部变量超标）
-- ══════════════════════════════════════════════════════════════════
local UI = {}
local COL = {
    Bg = Color3.fromRGB(24, 24, 28), Panel = Color3.fromRGB(32, 32, 38),
    Card = Color3.fromRGB(42, 42, 50), CardH = Color3.fromRGB(56, 56, 66),
    Line = Color3.fromRGB(58, 58, 68), Text = Color3.fromRGB(235, 235, 240),
    Sub = Color3.fromRGB(150, 150, 162), Acc = Color3.fromRGB(198, 40, 40),
    AccH = Color3.fromRGB(232, 66, 66), Ok = Color3.fromRGB(76, 175, 120),
}

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(r or 0, 8); c.Parent = p; return c
end
local function mkLabel(parent, size, pos, text, col, size_, xalign)
    local l = Instance.new("TextLabel")
    l.Size = size; l.Position = pos; l.BackgroundTransparency = 1
    l.Text = text or ""; l.TextColor3 = col or COL.Text
    l.TextSize = size_ or 14; l.Font = Enum.Font.Gotham
    l.TextXAlignment = xalign or Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end
local function mkBtn(parent, size, pos, text, bg, fg)
    local b = Instance.new("TextButton")
    b.Size = size; b.Position = pos
    b.BackgroundColor3 = bg or COL.Card; b.BorderSizePixel = 0
    b.Text = text or ""; b.TextColor3 = fg or COL.Text
    b.TextSize = 14; b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = false
    corner(b, 0)
    b.Parent = parent
    b.MouseEnter:Connect(function() b.BackgroundColor3 = COL.CardH end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = bg or COL.Card end)
    return b
end
local function mkInput(parent, size, pos, ph)
    local b = Instance.new("TextBox")
    b.Size = size; b.Position = pos
    b.BackgroundColor3 = COL.Card; b.BorderSizePixel = 0
    b.PlaceholderText = ph or ""; b.PlaceholderColor3 = COL.Sub
    b.Text = ""; b.TextColor3 = COL.Text; b.TextSize = 14
    b.Font = Enum.Font.Gotham; b.ClearTextOnFocus = false
    corner(b, 0)
    b.Parent = parent
    return b
end

-- 构建主窗口（可拖动）
function UI.buildWindow()
    local CoreGui = nil
    pcall(function() CoreGui = game:GetService("CoreGui") end)
    local parent = PlayerGui
    if CoreGui then
        local ok = pcall(function() local t = Instance.new("Folder"); t.Parent = CoreGui; t:Destroy() end)
        if ok then parent = CoreGui end
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NCM_V3"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    local win = Instance.new("Frame")
    win.Name = "Win"
    win.Size = UDim2.new(0, 680, 0, 440)
    win.Position = UDim2.new(0.5, -340, 0.5, -220)
    win.BackgroundColor3 = COL.Bg
    win.BorderSizePixel = 0
    win.Active = true
    corner(win, 0)
    win.Parent = gui

    -- 顶栏
    local top = Instance.new("Frame")
    top.Size = UDim2.new(1, 0, 0, 40); top.BackgroundColor3 = COL.Panel
    top.BorderSizePixel = 0; top.Parent = win
    mkLabel(top, UDim2.new(0, 200, 1, 0), UDim2.new(0, 14, 0, 0), "网易云音乐  v3.0", COL.Text, 15)

    local btnClose = mkBtn(top, UDim2.new(0, 30, 0, 26), UDim2.new(1, -38, 0, 7), "X", COL.Acc, COL.Text)
    local btnMin = mkBtn(top, UDim2.new(0, 30, 0, 26), UDim2.new(1, -74, 0, 7), "-", COL.Card, COL.Text)

    -- 悬浮的「恢复」按钮：窗口被关掉后靠它重新打开，
    -- 否则关一次就再也打不开了。
    local restore = Instance.new("TextButton")
    restore.Size = UDim2.new(0, 46, 0, 46)
    restore.Position = UDim2.new(0, 16, 0.5, -23)
    restore.BackgroundColor3 = COL.Acc
    restore.BorderSizePixel = 0
    restore.Text = "♪"
    restore.TextColor3 = COL.Text
    restore.TextSize = 20
    restore.Font = Enum.Font.GothamBold
    restore.Visible = false
    restore.Parent = gui
    corner(restore, 0)

    local function hideWin()
        win.Visible = false
        restore.Visible = true
    end
    local function showWin()
        win.Visible = true
        restore.Visible = false
    end
    btnClose.MouseButton1Click:Connect(hideWin)
    btnMin.MouseButton1Click:Connect(hideWin)
    restore.MouseButton1Click:Connect(showWin)

    -- 拖动
    do
        local dragging, dragStart, startPos = false, nil, nil
        top.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true; dragStart = i.Position; startPos = win.Position
            end
        end)
        top.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        UIS.InputChanged:Connect(function(i)
            if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                local d = i.Position - dragStart
                win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    return gui, win, top
end

-- 左侧标签栏 + 右侧内容区
function UI.buildLayout(win, top, tabs, onSelect)
    local side = Instance.new("Frame")
    side.Size = UDim2.new(0, 110, 1, -80)
    side.Position = UDim2.new(0, 0, 0, 40)
    side.BackgroundColor3 = COL.Panel
    side.BorderSizePixel = 0
    side.Parent = win

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -110, 1, -80)
    content.Position = UDim2.new(0, 110, 0, 40)
    content.BackgroundTransparency = 1
    content.Parent = win

    local pages, btns = {}, {}
    for i, name in ipairs(tabs) do
        local p = Instance.new("Frame")
        p.Size = UDim2.new(1, 0, 1, 0); p.BackgroundTransparency = 1
        p.Visible = (i == 1); p.Parent = content
        pages[i] = p

        local b = mkBtn(side, UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 0, 8 + (i - 1) * 40), name,
                        (i == 1) and COL.Acc or COL.Panel, COL.Text)
        btns[i] = b
        b.MouseButton1Click:Connect(function()
            for k = 1, #pages do
                pages[k].Visible = (k == i)
                btns[k].BackgroundColor3 = (k == i) and COL.Acc or COL.Panel
            end
            if onSelect then onSelect(i) end
        end)
        b.MouseEnter:Connect(function() if not pages[i].Visible then b.BackgroundColor3 = COL.Card end end)
        b.MouseLeave:Connect(function() if not pages[i].Visible then b.BackgroundColor3 = COL.Panel end end)
    end
    return pages
end

-- 歌曲列表（通用滚动列表）
-- 返回该页独立的 listApi（clear/fill/status）。
-- 注意：不能把这些方法挂到 UI 上共享 —— 每建一个页签都会覆盖，
-- 结果搜索结果会被画到别的页签里去。
function UI.buildList(page, onPick)
    local sc = Instance.new("ScrollingFrame")
    sc.Size = UDim2.new(1, -12, 1, -12)
    sc.Position = UDim2.new(0, 6, 0, 6)
    sc.BackgroundTransparency = 1
    sc.ScrollBarThickness = 6
    sc.ScrollBarImageColor3 = COL.Sub
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.BorderSizePixel = 0
    sc.Parent = page
    local lay = Instance.new("UIListLayout")
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Padding = UDim.new(0, 4)
    lay.Parent = sc
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sc.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 8)
    end)

    local function clear()
        for _, c in ipairs(sc:GetChildren()) do
            if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
        end
    end

    local function status(text)
        clear()
        local l = mkLabel(sc, UDim2.new(1, -12, 0, 30), UDim2.new(0, 6, 0, 6), text, COL.Sub, 13)
        l.TextWrapped = true
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.Size = UDim2.new(1, -12, 0, 60)
    end

    local function fill(songs)
        clear()
        for i, s in ipairs(songs) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -6, 0, 40)
            row.BackgroundColor3 = COL.Card
            row.BorderSizePixel = 0
            row.LayoutOrder = i
            corner(row, 0); row.Parent = sc
            mkLabel(row, UDim2.new(1, -170, 1, 0), UDim2.new(0, 12, 0, 0), s.name, COL.Text, 14)
            mkLabel(row, UDim2.new(0, 150, 1, 0), UDim2.new(1, -160, 0, 0), s.artist or "", COL.Sub, 12)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, 0, 1, 0); b.BackgroundTransparency = 1; b.Text = ""; b.Parent = row
            b.MouseButton1Click:Connect(function() onPick(s, i) end)
            b.MouseEnter:Connect(function() row.BackgroundColor3 = COL.CardH end)
            b.MouseLeave:Connect(function() row.BackgroundColor3 = COL.Card end)
        end
    end

    return { clear = clear, fill = fill, status = status, frame = sc }
end

-- 底部播放条
function UI.buildPlayerBar(win)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 64)
    bar.Position = UDim2.new(0, 0, 1, -64)
    bar.BackgroundColor3 = COL.Panel
    bar.BorderSizePixel = 0
    bar.Parent = win

    local btnPrev = mkBtn(bar, UDim2.new(0, 34, 0, 34), UDim2.new(0, 12, 0, 10), "|<", COL.Card)
    local btnPlay = mkBtn(bar, UDim2.new(0, 44, 0, 34), UDim2.new(0, 52, 0, 10), "▶", COL.Acc)
    local btnNext = mkBtn(bar, UDim2.new(0, 34, 0, 34), UDim2.new(0, 102, 0, 10), ">|", COL.Card)

    local title = mkLabel(bar, UDim2.new(0, 300, 0, 20), UDim2.new(0, 146, 0, 8), "未播放", COL.Text, 14)
    local timeL = mkLabel(bar, UDim2.new(0, 300, 0, 16), UDim2.new(0, 146, 0, 30), "0:00 / 0:00", COL.Sub, 12)

    local progBg = Instance.new("Frame")
    progBg.Size = UDim2.new(0, 300, 0, 4)
    progBg.Position = UDim2.new(0, 146, 0, 48)
    progBg.BackgroundColor3 = COL.Card
    progBg.BorderSizePixel = 0
    progBg.Parent = bar
    corner(progBg, 0)
    local prog = Instance.new("Frame")
    prog.Size = UDim2.new(0, 0, 1, 0)
    prog.BackgroundColor3 = COL.Acc
    prog.BorderSizePixel = 0
    prog.Parent = progBg
    corner(prog, 0)

    local volL = mkLabel(bar, UDim2.new(0, 40, 0, 18), UDim2.new(1, -160, 0, 10), "音量", COL.Sub, 12)
    local volBg = Instance.new("Frame")
    volBg.Size = UDim2.new(0, 100, 0, 4)
    volBg.Position = UDim2.new(1, -150, 0, 18)
    volBg.BackgroundColor3 = COL.Card
    volBg.BorderSizePixel = 0
    volBg.Parent = bar
    corner(volBg, 0)
    local vol = Instance.new("Frame")
    vol.Size = UDim2.new(0.6, 0, 1, 0)
    vol.BackgroundColor3 = COL.Ok
    vol.BorderSizePixel = 0
    vol.Parent = volBg
    corner(vol, 0)

    btnPrev.MouseButton1Click:Connect(function() Player.prev_() end)
    btnNext.MouseButton1Click:Connect(function() Player.next_() end)
    btnPlay.MouseButton1Click:Connect(function() Player.toggle() end)

    -- 进度条拖动
    local seeking = false
    local function setProg(x)
        local rel = math.clamp((x - progBg.AbsolutePosition.X) / progBg.AbsoluteSize.X, 0, 1)
        prog.Size = UDim2.new(rel, 0, 1, 0)
        local s = Player.sound
        if s and s.TimeLength > 0 then Player.seek(rel * s.TimeLength) end
    end
    progBg.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            seeking = true; setProg(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if seeking and i.UserInputType == Enum.UserInputType.MouseMovement then setProg(i.Position.X) end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then seeking = false end
    end)

    local vseek = false
    local function setVol(x)
        local rel = math.clamp((x - volBg.AbsolutePosition.X) / volBg.AbsoluteSize.X, 0, 1)
        vol.Size = UDim2.new(rel, 0, 1, 0)
        Player.setVolume(rel)
    end
    volBg.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then vseek = true; setVol(i.Position.X) end
    end)
    UIS.InputChanged:Connect(function(i)
        if vseek and i.UserInputType == Enum.UserInputType.MouseMovement then setVol(i.Position.X) end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then vseek = false end
    end)

    local function fmt(t)
        t = math.floor(t or 0)
        return string.format("%d:%02d", math.floor(t / 60), t % 60)
    end

    RunService.Heartbeat:Connect(function()
        local s = Player.sound
        if Player.current then
            title.Text = Player.current.name .. "  -  " .. (Player.current.artist or "")
        end
        if s and s.TimeLength > 0 then
            local rel = s.TimePosition / s.TimeLength
            if not seeking then prog.Size = UDim2.new(math.clamp(rel, 0, 1), 0, 1, 0) end
            timeL.Text = fmt(s.TimePosition) .. " / " .. fmt(s.TimeLength)
            if s.IsPlaying then
                btnPlay.Text = "||"
            else
                btnPlay.Text = "▶"
                -- 只自动切一次：否则播完停在末尾会每帧都触发 next_
                if rel >= 0.999 and not Player.autoNexted then
                    Player.autoNexted = true
                    Player.next_()
                end
            end
        end
        if Player.status and Player.status ~= "" then
            timeL.Text = Player.status
        end
    end)

    return bar
end

-- 歌词面板
function UI.buildLyric(win)
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 260, 1, -104)
    panel.Position = UDim2.new(1, -270, 0, 40)
    panel.BackgroundColor3 = COL.Panel
    panel.BorderSizePixel = 0
    panel.Visible = false
    corner(panel, 0)
    panel.Parent = win

    local sc = Instance.new("ScrollingFrame")
    sc.Size = UDim2.new(1, -8, 1, -8)
    sc.Position = UDim2.new(0, 4, 0, 4)
    sc.BackgroundTransparency = 1
    sc.ScrollBarThickness = 4
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.Parent = panel
    local lay = Instance.new("UIListLayout")
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Padding = UDim.new(0, 6)
    lay.Parent = sc

    local labels = {}
    local function rebuild()
        for _, l in ipairs(labels) do l:Destroy() end
        labels = {}
        if not Player.lyricLines then return end
        for i, ln in ipairs(Player.lyricLines) do
            local l = mkLabel(sc, UDim2.new(1, -10, 0, 20), UDim2.new(0, 0, 0, 0), ln.text, COL.Sub, 13)
            l.TextWrapped = true
            l.LayoutOrder = i
            labels[i] = l
        end
        sc.CanvasSize = UDim2.new(0, 0, 0, #labels * 26 + 10)
    end

    local lastIdx = 0
    RunService.Heartbeat:Connect(function()
        if not panel.Visible then return end
        local s = Player.sound
        local lines = Player.lyricLines
        if not s or not lines or #lines == 0 then return end
        local t = s.TimePosition
        local idx = 0
        for i = 1, #lines do if lines[i].t <= t then idx = i else break end end
        if idx ~= lastIdx then
            lastIdx = idx
            for i, l in ipairs(labels) do
                l.TextColor3 = (i == idx) and COL.Acc or COL.Sub
                l.TextSize = (i == idx) and 15 or 13
            end
            if idx > 0 then sc.CanvasPosition = Vector2.new(0, math.max(0, (idx - 3) * 26)) end
        end
    end)

    Player.onUpdate = function() rebuild(); lastIdx = 0 end
    return panel
end

-- ══════════════════════════════════════════════════════════════════
-- 组装各页签
-- ══════════════════════════════════════════════════════════════════
local function buildSearchPage(page, onPlay)
    local box = mkInput(page, UDim2.new(1, -110, 0, 32), UDim2.new(0, 8, 0, 8), "搜索歌曲 / 歌手")
    local btn = mkBtn(page, UDim2.new(0, 90, 0, 32), UDim2.new(1, -98, 0, 8), "搜索", COL.Acc)

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -16, 1, -56)
    holder.Position = UDim2.new(0, 8, 0, 48)
    holder.BackgroundTransparency = 1
    holder.Parent = page

    local L = UI.buildList(holder, function(s, i) onPlay(s) end)
    L.status("输入关键词后点搜索")

    local function doSearch()
        local kw = box.Text
        if kw == nil or kw == "" then return end
        L.status("搜索中…")
        taskLib.spawn(function()
            local res = Api.search(kw, 30)
            if #res == 0 then
                L.status("没有结果")
            else
                L.fill(res)
            end
        end)
    end

    btn.MouseButton1Click:Connect(doSearch)
    -- 回车搜索（旧版这里错误地对事件调用了 :Fire()，导致
    -- "Fire is not a valid member of RBXScriptSignal"，改为直接调用处理函数）
    box.FocusLost:Connect(function(enter) if enter then doSearch() end end)
end

local function buildLikedPage(page, onPlay)
    local btnRefresh = mkBtn(page, UDim2.new(0, 110, 0, 30), UDim2.new(1, -118, 0, 8), "刷新红心", COL.Acc)

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -16, 1, -52)
    holder.Position = UDim2.new(0, 8, 0, 46)
    holder.BackgroundTransparency = 1
    holder.Parent = page

    local L = UI.buildList(holder, function(s, i) onPlay(s) end)

    local function refresh(force)
        if not Liked.userId then
            L.status("未登录：登录后可显示云端「我喜欢的音乐」。\n下面是本地收藏：")
            if #Fav.list > 0 then L.fill(Fav.list) end
            return
        end
        L.status("正在拉取云端红心歌单…")
        taskLib.spawn(function()
            local songs, err = Liked.songs(force)
            if err or #songs == 0 then
                L.status("云端红心为空或拉取失败：" .. tostring(err or "无") .. "\n本地收藏：")
                if #Fav.list > 0 then L.fill(Fav.list) end
            else
                L.fill(songs)
            end
        end)
    end

    btnRefresh.MouseButton1Click:Connect(function() refresh(true) end)
    refresh(false)
    return refresh
end

local function buildQueuePage(page, onPlay)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -16, 1, -16)
    holder.Position = UDim2.new(0, 8, 0, 8)
    holder.BackgroundTransparency = 1
    holder.Parent = page

    local L = UI.buildList(holder, function(s, i)
        Player.index = i
        onPlay(s)
    end)

    local function refresh()
        if #Player.queue == 0 then L.status("播放列表为空") else L.fill(Player.queue) end
    end
    refresh()
    return refresh
end

local function buildLoginPage(page, refreshLiked)
    local y = 8
    mkLabel(page, UDim2.new(1, -16, 0, 20), UDim2.new(0, 8, 0, y), "① Cookie 登录（最稳）", COL.Text, 14); y = y + 24
    local ck = mkInput(page, UDim2.new(1, -16, 0, 32), UDim2.new(0, 8, 0, y), "粘贴浏览器复制的 Cookie"); y = y + 40
    local btnCk = mkBtn(page, UDim2.new(0, 120, 0, 30), UDim2.new(0, 8, 0, y), "Cookie 登录", COL.Acc)
    local st = mkLabel(page, UDim2.new(1, -150, 0, 30), UDim2.new(0, 136, 0, y), "未登录", COL.Sub, 12)
    y = y + 46

    mkLabel(page, UDim2.new(1, -16, 0, 20), UDim2.new(0, 8, 0, y), "② 短信验证码登录（内置 WEAPI，不依赖第三方）", COL.Text, 14); y = y + 24
    local ph = mkInput(page, UDim2.new(0, 180, 0, 32), UDim2.new(0, 8, 0, y), "手机号")
    local btnSend = mkBtn(page, UDim2.new(0, 90, 0, 32), UDim2.new(0, 196, 0, y), "发验证码", COL.Card)
    y = y + 40
    local code = mkInput(page, UDim2.new(0, 180, 0, 32), UDim2.new(0, 8, 0, y), "验证码")
    local btnVerify = mkBtn(page, UDim2.new(0, 90, 0, 32), UDim2.new(0, 196, 0, y), "登录", COL.Acc)
    y = y + 46

    local tip = mkLabel(page, UDim2.new(1, -16, 0, 60), UDim2.new(0, 8, 0, y),
        "提示：验证码登录成功后会自动保存 Cookie。若接口变更导致失败，请用方式①。", COL.Sub, 12)
    tip.TextWrapped = true

    local function setStatus(text, col)
        st.Text = text; st.TextColor3 = col or COL.Sub
    end

    btnCk.MouseButton1Click:Connect(function()
        if ck.Text == nil or ck.Text == "" then setStatus("请先粘贴 Cookie", COL.AccH); return end
        setStatus("验证中…", COL.Sub)
        taskLib.spawn(function()
            local ok, acc = Login.byCookie(ck.Text)
            if ok then
                setStatus("已登录：" .. tostring(acc.nickname) .. "（" .. tostring(acc.vipName) .. "）", COL.Ok)
                if refreshLiked then refreshLiked(true) end
            else
                setStatus("登录失败：Cookie 无效或已过期", COL.AccH)
            end
        end)
    end)

    btnSend.MouseButton1Click:Connect(function()
        if ph.Text == nil or ph.Text == "" then setStatus("请输入手机号", COL.AccH); return end
        setStatus("发送中…", COL.Sub)
        taskLib.spawn(function()
            local ok, msg = Login.smsSend(ph.Text, "86")
            setStatus(msg, ok and COL.Ok or COL.AccH)
        end)
    end)

    btnVerify.MouseButton1Click:Connect(function()
        if ph.Text == nil or ph.Text == "" or code.Text == nil or code.Text == "" then
            setStatus("请填手机号和验证码", COL.AccH); return
        end
        setStatus("登录中…", COL.Sub)
        taskLib.spawn(function()
            local ok, acc = Login.smsVerify(ph.Text, code.Text, "86")
            if ok then
                setStatus("已登录：" .. tostring(acc.nickname) .. "（" .. tostring(acc.vipName) .. "）", COL.Ok)
                if refreshLiked then refreshLiked(true) end
            else
                setStatus(tostring(acc), COL.AccH)
            end
        end)
    end)

    -- 启动时自动载入已保存的 Cookie
    taskLib.spawn(function()
        local saved = Login.loadCookie()
        if saved ~= "" then
            ck.Text = saved
            local acc = Api.account()
            if acc then
                Liked.setUser(acc.userId)
                setStatus("已登录：" .. tostring(acc.nickname) .. "（" .. tostring(acc.vipName) .. "）", COL.Ok)
            else
                setStatus("已保存的 Cookie 已失效", COL.AccH)
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 主流程
-- ══════════════════════════════════════════════════════════════════
local function main()
    math.randomseed(os.time() + tick())
    Fav.load()

    -- Headless：只要引擎，不建自带 UI（外部界面负责显示）
    if HEADLESS then
        print("[NCM] Headless 模式：引擎已就绪，未构建自带 UI")
        return
    end

    local gui, win, top = UI.buildWindow()
    local lyricPanel = UI.buildLyric(win)

    local function onPlay(song)
        -- 把当前列表并入播放队列（简单策略：当前点击的歌放到队列并播放）
        if #Player.queue == 0 then Player.queue = { song }; Player.index = 1 end
        local found = false
        for i, s in ipairs(Player.queue) do if s.id == song.id then Player.index = i; found = true; break end end
        if not found then
            Player.queue[#Player.queue + 1] = song
            Player.index = #Player.queue
        end
        local ok, err = Player.play(song)
        if not ok then warn("[NCM] " .. tostring(err)) end
    end

    local pages = UI.buildLayout(win, top, { "搜索", "我喜欢的", "播放列表", "登录" }, nil)
    buildSearchPage(pages[1], onPlay)
    local refreshLiked = buildLikedPage(pages[2], onPlay)
    local refreshQueue = buildQueuePage(pages[3], onPlay)
    buildLoginPage(pages[4], refreshLiked)
    UI.buildPlayerBar(win)

    local oldPlay = Player.play
    Player.play = function(song)
        local ok, err = oldPlay(song)
        if refreshQueue then refreshQueue() end
        return ok, err
    end

    -- 歌词开关按钮
    local btnLyric = mkBtn(top, UDim2.new(0, 30, 0, 26), UDim2.new(1, -110, 0, 7), "词", COL.Card, COL.Text)
    btnLyric.MouseButton1Click:Connect(function()
        lyricPanel.Visible = not lyricPanel.Visible
        btnLyric.BackgroundColor3 = lyricPanel.Visible and COL.Acc or COL.Card
    end)

    print("[NCM v3.2] 已加载。UI 自制，WEAPI 内置，启动自动恢复登录 Cookie，引擎已导出。")
end

-- ══════════════════════════════════════════════════════════════════
-- v3.1 修复：启动时立刻恢复登录态
--   旧版把 loadCookie 放在「登录」页构建函数里，而且只 return 不写回 Net.cookie，
--   导致脚本启动后始终是未登录状态：VIP 歌（搜索结果的绝大多数）取直链返回空，
--   表现就是「点了歌不出声 / 播放功能坏了」。
--   这里在 main() 之前就把 Cookie 灌进内存，保证第一个请求就是已登录的。
-- ══════════════════════════════════════════════════════════════════
pcall(function()
    local c = Login.loadCookie()
    if c ~= "" then
        print("[NCM] 已恢复登录 Cookie（" .. #c .. " 字符）")
    else
        print("[NCM] 未找到已保存的 Cookie，将以未登录状态运行（VIP 歌无法播放）")
    end
end)

local ok, err = pcall(main)
if not ok then
    warn("[NCM v3.2] 启动失败: " .. tostring(err))
end

-- ══════════════════════════════════════════════════════════════════
-- v3.2：引擎出口
--   把内部模块打包成一个稳定接口挂到 getgenv().NCM，外部 UI 只依赖这一层，
--   不用碰内部字段名。uilib 的 MUSIC 分支用 MusicUI.BindNetease(getgenv().NCM) 接入。
-- ══════════════════════════════════════════════════════════════════
pcall(function()
    local g = (getgenv and getgenv()) or _G
    g.NCM = {
        version = "v3.2",
        headless = HEADLESS,

        -- 原始模块（需要更细的控制时用）
        Api = Api, Player = Player, Net = Net, Weapi = Weapi,
        Liked = Liked, Login = Login, Fav = Fav, CFG = CFG,

        -- 执行器工具
        fnAsset = fnAsset, fnWrite = fnWrite, fnRead = fnRead,
        fnIsFile = fnIsFile, fnIsFold = fnIsFold, fnMkDir = fnMkDir,
        songPath = songPath, rawRequest = rawRequest,

        -- 便捷封装：外部 UI 推荐只用这些
        Search    = function(kw, limit) return Api.search(kw, limit) end,
        SearchLiked = function(force) return Liked.songs(force) end,
        GetAccount  = function() return Api.account() end,
        IsLoggedIn  = function() local a = Api.account(); return a ~= nil, a end,

        Play      = function(song) return Player.play(song) end,
        Toggle    = function() Player.toggle() end,
        Next      = function() Player.next_() end,
        Prev      = function() Player.prev_() end,
        Seek      = function(sec) Player.seek(sec) end,
        SetVolume = function(v) Player.setVolume(v) end,
        SetQueue  = function(list, i) return Player.setQueue(list, i) end,
        PlayAt    = function(i) return Player.playAt(i) end,
        GetState  = function() return Player.getState() end,
        LyricAt   = function(pos) return Player.lyricAt(pos) end,
        LyricLines = function() return Player.lyricLines end,

        -- 本地收藏（与云端红心无关）
        FavList   = function() return Fav.list end,
        FavHas    = function(id) return Fav.has({ id = id }) end,
        FavToggle = function(song) return Fav.toggle(song) end,
    }
    print("[NCM] 引擎已导出到 getgenv().NCM（" .. (HEADLESS and "Headless" or "带 UI") .. " 模式）")
end)
