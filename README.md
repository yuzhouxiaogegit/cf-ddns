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
# Cloudflare 的 API Token
CF_TOKEN="您的Cloudflare API Token" 

# cloudflare 的顶级域名
CFZONE_NAME="您的顶级域名 (例如：mydomain.com)"

# cloudflare 的对应 ddns 域名
CFRECORD_NAME="您要更新的DDNS域名 (例如：home.mydomain.com)" 

# 记录类型，A(IPv4)|AAAA(IPv6)，默认 IPv4
CFRECORD_TYPE="A" 

# DNS 记录的代理状态: true (开启代理) | false (仅DNS)
CFPROXIED=false
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
