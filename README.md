# netease_music
网易云音乐下载 http://music.163.com

# 安装

以 archlinux 环境为例

安装firefox浏览器，安装firefox的[mozrepl](https://addons.mozilla.org/en-US/firefox/addon/mozrepl/)扩展，打开firefox，启动mozrepl

    sudo pacman -S tcpdump wireshark-cli wireshark-common 
    sudo pacman -S curl
    cpan App::cpanminus
    cpanm -n -f WWW::Mechanize::Firefox JSON Encode::Locale

# 分析

网易云音乐需要点击播放，页面使用ajax POST请求自动获取音乐地址

(法一，使用headless browser直接提供ajax应答数据的缓存)

(法二，使用http代理，headless browser自动访问，代理提供ajax应答数据的缓存)

法三，调用browser接口自动访问专辑，抓包解析出mp3地址

使用tcpdump监听80端口流量，写到pcap文件

使用WWW::Mechanize::Firefox调用firefox遍历指定的音乐专辑，自动打开每个音乐文件页面（点击播放，等待3秒）

浏览器访问结束后，停止tcpdump监听

调用tshark解析出pcap文件中记录的mp3文件地址

根据已解析的音乐信息和mp3文件地址列表，调用curl下载专辑音乐到本地

# 用法

## 专辑

perl netease_music.pl [album_url]

    perl netease_music.pl "http://music.163.com/#/album?id=14390" | tee netease_album.log
    
example album download log: [netease_album.log](netease_album.log)

    > tree 任贤齐-老地方 
    任贤齐-老地方
    ├── 01.戏迷.mp3
    ├── 02.约定蓝天.mp3
    ├── 03.老地方.mp3
    ├── 04.好时代.mp3
    ├── 05.爱伤了.mp3
    ├── 06.外婆桥.mp3
    ├── 07.天生注定.mp3
    ├── 08.秋天来了.mp3
    ├── 09.我就在你身边.mp3
    └── 10.想飞.mp3

    0 directories, 10 files

## 歌单

perl netease_music.pl [playlist_url]

    perl netease_music.pl "http://music.163.com/#/playlist?id=161864761" | tee netease_playlist.log

example playlist download log: [netease_playlist.log](netease_playlist.log)

