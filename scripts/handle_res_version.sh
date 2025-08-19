#!/bin/bash

endpoint="https://api.link-like-lovelive.app/v1/user/login"
client_version="4.5.0"
res_version="R2503000"
res_version_file="../data/res_version.txt"

# 创建data目录（如果不存在）
mkdir -p "../data"

# 标记是否有新版本
has_new_version=false

# 执行curl请求并捕获响应头
response_headers=$(curl -s -D - "$endpoint" \
     -H "content-type: application/json" \
     -H "x-client-version: $client_version" \
     -H "user-agent: inspix-android/$client_version" \
     -H "x-res-version: $res_version" \
     -H "x-device-type: android" \
     -d '{"device_specific_id":"","player_id":"","version":1}')

# 提取x-res-version的值
new_res_version=$(echo "$response_headers" | grep -i "x-res-version:" | sed 's/.*x-res-version: *//i' | tr -d '\r\n')

if [ -n "$new_res_version" ]; then
    echo "获取到新的资源版本: $new_res_version"
    echo 
    # 检查该版本是否已存在于文件中
    if [ -f "$res_version_file" ] && grep -Fxq "$new_res_version" "$res_version_file"; then
        echo "版本 $new_res_version 已存在，跳过写入"
    else
        # 创建临时文件，将新版本写入第一行，然后追加现有内容
        if [ -f "$res_version_file" ]; then
            # 文件存在，将新版本添加到第一行
            echo "$new_res_version" > temp_res_version.txt
            cat "$res_version_file" >> temp_res_version.txt
            mv temp_res_version.txt "$res_version_file"
        else
            # 文件不存在，直接创建
            echo "$new_res_version" > "$res_version_file"
        fi
        echo "新版本 $new_res_version 已写入到 $res_version_file"
        has_new_version=true
    fi
else
    echo "未能获取到x-res-version值"
fi

# 根据是否有新版本设置退出码
if [ "$has_new_version" = true ]; then
    echo "检测到新版本，退出码: 0"
    exit 0
else
    echo "无新版本，退出码: 1"
    exit 1
fi