#!/bin/bash

#cloudflare的帐号
auth_email=""
#cloudflare的密钥
auth_key=""
#cloudflare的顶级域名
zone_name=""
#cloudflare的对应ddns域名
record_name=""
#需要通知的邮箱
email=""

#检查ip地址的网站
ip=$(curl -s http://ipv4.icanhazip.com)
#本地存储ip的文件
ip_file="/usr/local/bin/ip.txt"
#cloudflare的ids文件
id_file="/usr/local/bin/cloudflare.ids"
#cloudflare的日志文件
log_file="/usr/local/bin/cloudflare.log"

# 日志打印
log() {
    if [ "$1" ]; then
        echo -e "[$(date)] - $1" >> $log_file
    fi
}

#判断获取到ip是否正常
if [ ! -n "$ip" ]; then
	echo "IS NULL"
	exit 0
else
  	echo "NOT NULL"
fi

#判断ip是否改变
if [ -f $ip_file ]; then
    old_ip=$(cat $ip_file)
    if [ $ip == $old_ip ]; then
        echo "IP has not changed."
        exit 0
    fi
fi

#ip改变了
#提交给cloudflare同步ip
if [ -f $id_file ] && [ $(wc -l $id_file | cut -d " " -f 1) == 2 ]; then
    zone_identifier=$(head -1 $id_file)
    record_identifier=$(tail -1 $id_file)
else
    zone_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    record_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*')
    echo "$zone_identifier" > $id_file
    echo "$record_identifier" >> $id_file
fi

update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" --data "{\"id\":\"$zone_identifier\",\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\"}")

#更新失败
if [[ $update == *"\"success\":false"* ]]; then
    message="API UPDATE FAILED. DUMPING RESULTS:\n$update"
    echo -e "$message"
#邮件提醒更新失败原因
	curl "http://blog.mojxtang.com/mail/sendmail.php?toemail=$email&title=FAIL&content=$record_name error:$message"
    exit 0
else
#更新成功
    message="IP changed to: $ip"
    echo "$ip" > $ip_file
    log "$message"
    echo "$message"
#邮件提醒，ip更换成功了。
	curl "http://blog.mojxtang.com/mail/sendmail.php?toemail=$email&title=SUCCESS&content=$record_name IP Changed to: $ip"

fi