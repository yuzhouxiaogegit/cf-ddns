# 动态ddns解析，支持ipv6

### 下载cf-ddns脚本
```code
curl -Lo cf-ddns.sh https://raw.githubusercontent.com/yuzhouxiaogegit/cf-ddns/master/cf-ddns.sh && chmod +x cf-ddns.sh
```
### 编辑文件
```code
vi cf-ddns.sh
```
### 【Global API Key】生成地址： https://dash.cloudflare.com/profile/api-tokens
### 编辑内容为
```code 
#cloudflare的CFKEY【Global API Key】
CFKEY=

#cloudflare的帐号【邮箱】
CFUSER=

#cloudflare的顶级域名
CFZONE_NAME=

#cloudflare的对应ddns域名
CFRECORD_NAME=

# 记录类型，A(IPv4)|AAAA(IPv6)，默认 IPv4
CFRECORD_TYPE=A
```
### 设置定时任务、输入 crontab -e  然后会弹出 vi 编辑界面，按小写字母 i 进入编辑模式，在文件里面添加一行
```code
*/2 * * * * /root/cf-ddns.sh >/dev/null 2>&1
```
### 如果您需要日志文件，上述代码请替换成下面代码
```code
*/2 * * * * /root/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1
```
### 重载定时任务配置
```code
systemctl reload crond.service
```
### 重启定时任务
```code
systemctl restart crond.service
```
