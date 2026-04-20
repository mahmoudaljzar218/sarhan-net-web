#!/bin/sh

# ============================================
# سكريبت السرحان NET - النسخة الخامسة مع رفع الأجهزة
# ============================================

DB_URL="https://sarhan-net-70a77-default-rtdb.firebaseio.com/active_users.json"
DEVICES_URL="https://sarhan-net-70a77-default-rtdb.firebaseio.com/network/devices.json"
INTERFACE="br-lan"
LOG_FILE="/var/log/sarhan_net.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# 1. تنظيف القواعد والسرعات القديمة
cleanup_rules() {
    # حذف أي قواعد سماح قديمة للماك أدرس
    iptables -D FORWARD -m mac --mac-source -j ACCEPT 2>/dev/null
    # تنظيف نظام تحديد السرعات
    tc qdisc del dev $INTERFACE root 2>/dev/null
}

# 2. بناء سجن الفايروول (الـ Walled Garden)
set_security() {
    iptables -P FORWARD DROP
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # الخروم المسموح بها (DNS + صفحتك + تليجرام + فايربيز)
    iptables -A FORWARD -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -p tcp -d mahmoudaljzar218.github.io -j ACCEPT
    iptables -A FORWARD -p tcp -d firebaseio.com -j ACCEPT
    iptables -A FORWARD -p tcp -d googleapis.com -j ACCEPT
    iptables -A FORWARD -p tcp -d api.telegram.org -j ACCEPT
}

# 3. دالة جديدة: سحب الأجهزة المتصلة ورفعها إلى Firebase
upload_connected_devices() {
    # استخراج MAC + IP من جدول ARP
    DEVICES_JSON="["
    while IFS= read -r line; do
        ip=$(echo "$line" | awk '{print $1}')
        mac=$(echo "$line" | awk '{print $4}' | tr '[:lower:]' '[:upper:]')
        
        if [ "$mac" != "00:00:00:00:00:00" ] && [ ! -z "$mac" ] && [ "$mac" != "IP" ] && [ "$ip" != "Address" ]; then
            DEVICES_JSON="${DEVICES_JSON}{\"mac\":\"$mac\",\"ip\":\"$ip\",\"status\":\"online\",\"last_seen\":\"$(date -Iseconds)\"},"
        fi
    done < /proc/net/arp
    
    # إزالة الفاصلة الزائدة إذا وجدت
    DEVICES_JSON="${DEVICES_JSON%,}]"
    
    # رفع البيانات إلى Firebase
    if [ "$DEVICES_JSON" != "]" ] && [ "$DEVICES_JSON" != "[" ]; then
        wget -qO- --method=PUT --body-data="$DEVICES_JSON" \
            --header="Content-Type: application/json" \
            "$DEVICES_URL" > /dev/null 2>&1
        log_message "تم رفع الأجهزة المتصلة إلى Firebase"
    else
        # لو مفيش أجهزة، نرفع مصفوفة فاضية
        wget -qO- --method=PUT --body-data="[]" \
            --header="Content-Type: application/json" \
            "$DEVICES_URL" > /dev/null 2>&1
        log_message "لا توجد أجهزة متصلة حالياً"
    fi
}

# 4. المزامنة ومعالجة البيانات
sync_now() {
    # جلب البيانات بـ wget (الأداة الرسمية للراوتر)
    DATA=$(wget -qO- "$DB_URL")
    
    if [ -z "$DATA" ] || [ "$DATA" = "null" ]; then
        log_message "السيرفر لا يرد أو لا يوجد مشتركين حالياً"
        # حتى لو مفيش مشتركين، نرفع الأجهزة المتصلة
        upload_connected_devices
        return
    fi

    cleanup_rules
    set_security
    
    # إعداد محرك السرعات (HTB)
    tc qdisc add dev $INTERFACE root handle 1: htb default 30
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit

    active_count=0
    
    # استخراج البيانات يدوياً (بديل jq)
    # بنقطع الـ JSON لكل مستخدم في سطر
    echo "$DATA" | sed 's/},{/\n/g' | while read -r user; do
        # استخراج الماك وتحويله لحروف كبيرة
        mac=$(echo "$user" | grep -o '\"mac\":\"[^\"]*\"' | cut -d'"' -f4 | tr '[:lower:]' '[:upper:]')
        status=$(echo "$user" | grep -o '\"status\":\"[^\"]*\"' | cut -d'"' -f4)
        speed=$(echo "$user" | grep -o '\"speed_limit\":[0-9]*' | cut -d':' -f2)
        
        [ -z "$speed" ] && speed=10 # لو مفيش سرعة محددة ندي 10 ميجا

        if [ "$status" = "active" ] && [ ! -z "$mac" ]; then
            # فتح النت الكامل لهذا الجهاز
            iptables -I FORWARD -m mac --mac-source "$mac" -j ACCEPT
            
            # تطبيق السرعة عليه
            active_count=$((active_count + 1))
            classid=$((10 + active_count))
            tc class add dev $INTERFACE parent 1: classid 1:$classid htb rate ${speed}mbit ceil ${speed}mbit
            tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match u32 0 0 flowid 1:$classid
            
            log_message "تم فتح النت لـ $mac بسرعـة ${speed} ميجا"
        fi
    done
    
    # بعد تطبيق القواعد، نقوم برفع الأجهزة المتصلة
    upload_connected_devices
}

# التشغيل الفعلي
sync_now
