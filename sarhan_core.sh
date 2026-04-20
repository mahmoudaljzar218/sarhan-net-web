#!/bin/sh

# ============================================
# سكريبت الراوتر - السرحان NET
# يقرأ من active_users ويفتح النت للأجهزة المسموحة فقط
# ============================================

# إعدادات المسارات
DB_URL="https://sarhan-net-70a77-default-rtdb.firebaseio.com/active_users.json"
INTERFACE="br-lan"
LOCK_FILE="/tmp/sarhan_sync.lock"
LOG_FILE="/var/log/sarhan_net.log"

# دوال مساعدة
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# التحقق من وجود الأدوات المطلوبة
check_dependencies() {
    if ! command -v curl &> /dev/null; then
        echo "curl not found, installing..."
        opkg update && opkg install curl
    fi
    if ! command -v jq &> /dev/null; then
        echo "jq not found, installing..."
        opkg update && opkg install jq
    fi
    if ! command -v bc &> /dev/null; then
        echo "bc not found, installing..."
        opkg update && opkg install bc
    fi
    if ! command -v iptables &> /dev/null; then
        echo "iptables not found, installing..."
        opkg update && opkg install iptables iptables-mod-extra
    fi
    if ! command -v ebtables &> /dev/null; then
        echo "ebtables not found, installing..."
        opkg update && opkg install ebtables
    fi
    if ! command -v tc &> /dev/null; then
        echo "tc not found, installing..."
        opkg update && opkg install tc
    fi
}

# تنظيف القواعد القديمة قبل إضافة قواعد جديدة
cleanup_rules() {
    log_message "تنظيف القواعد القديمة..."
    
    # مسح قواعد iptables الخاصة بـ FORWARD (باستثناء القواعد الأساسية)
    iptables -D FORWARD -m mac --mac-source -j ACCEPT 2>/dev/null
    iptables -D FORWARD -m mac --mac-source -j DROP 2>/dev/null
    
    # مسح قواعد ebtables الخاصة بـ FORWARD
    ebtables -t filter -F FORWARD 2>/dev/null
    
    # إعادة تعيين tc
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev ifb0 root 2>/dev/null
    
    # تنظيف قواعد ingress
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    
    log_message "تم تنظيف القواعد القديمة"
}

# تطبيق قواعد السرعة على جهاز معين
apply_speed_limit() {
    local mac=$1
    local speed_down=$2
    local speed_up=$3
    
    # تحويل السرعة من Mbps إلى kbps
    local speed_down_kbit=$(echo "$speed_down * 1024" | bc 2>/dev/null || echo "10240")
    local speed_up_kbit=$(echo "$speed_up * 1024" | bc 2>/dev/null || echo "5120")
    
    # التأكد من أن السرعة رقم موجب
    if [ -z "$speed_down_kbit" ] || [ "$speed_down_kbit" -le 0 ]; then
        speed_down_kbit=10240  # 10 Mbps افتراضي
    fi
    if [ -z "$speed_up_kbit" ] || [ "$speed_up_kbit" -le 0 ]; then
        speed_up_kbit=5120     # 5 Mbps افتراضي
    fi
    
    # إنشاء قواعد HTB للتحميل
    tc qdisc add dev $INTERFACE root handle 1: htb default 30 2>/dev/null
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit 2>/dev/null
    tc class add dev $INTERFACE parent 1:1 classid 1:$mac htb rate ${speed_down_kbit}kbit ceil ${speed_down_kbit}kbit 2>/dev/null
    tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match u32 0 0 flowid 1:$mac 2>/dev/null
    
    # تطبيق على upload (باستخدام ifb)
    modprobe ifb 2>/dev/null
    ip link set ifb0 up 2>/dev/null
    tc qdisc add dev $INTERFACE handle ffff: ingress 2>/dev/null
    tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0 2>/dev/null
    tc qdisc add dev ifb0 root handle 2: htb default 30 2>/dev/null
    tc class add dev ifb0 parent 2: classid 2:1 htb rate 1000mbit 2>/dev/null
    tc class add dev ifb0 parent 2:1 classid 2:$mac htb rate ${speed_up_kbit}kbit ceil ${speed_up_kbit}kbit 2>/dev/null
    tc filter add dev ifb0 parent 2: protocol ip prio 1 u32 match u32 0 0 flowid 2:$mac 2>/dev/null
    
    log_message "تم تطبيق السرعة على $mac: تحميل ${speed_down}Mbps, رفع ${speed_up}Mbps"
}

# فتح جهاز (السماح بالاتصال)
allow_device() {
    local mac=$1
    
    # إضافة قاعدة سماح في iptables
    iptables -I FORWARD -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null
    
    log_message "تم فتح الجهاز $mac"
}

# حظر جهاز (قطع النت)
block_device() {
    local mac=$1
    
    # إضافة قاعدة حظر في iptables
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null
    ebtables -t filter -A FORWARD -s "$mac" -j DROP 2>/dev/null
    
    log_message "تم حظر الجهاز $mac"
}

# المزامنة الرئيسية - تقرأ من active_users وتطبق القواعد
sync_network() {
    # منع التشغيل المتزامن
    if [ -f "$LOCK_FILE" ]; then
        log_message "المزامنة قيد التشغيل بالفعل، تخطي..."
        return
    fi
    touch "$LOCK_FILE"
    
    log_message "بدء مزامنة الشبكة..."
    
    # جلب البيانات من Firebase - السكريبت يدور في active_users.json
    DATA=$(curl -s "$DB_URL" 2>/dev/null)
    
    if [ -z "$DATA" ] || [ "$DATA" = "null" ]; then
        log_message "فشل جلب البيانات من Firebase"
        rm -f "$LOCK_FILE"
        return
    fi
    
    # قائمة الماك المستخدمة (لمنع الحظر الخاطئ)
    active_macs=""
    
    # معالجة البيانات - السكريبت هياخد الماك اللي أنت حددته في الأدمن
    echo "$DATA" | jq -r 'to_entries[] | "\(.key)|\(.value.mac // "00:00:00:00:00:00")|\(.value.status // "inactive")|\(.value.remainingGB // 0)|\(.value.speed_limit // 10)|\(.value.speed_up // 5)"' 2>/dev/null | while IFS='|' read -r phone mac status remaining speed_down speed_up; do
        
        # تحويل الماك لأحرف كبيرة
        mac=$(echo "$mac" | tr '[:lower:]' '[:upper:]' | xargs)
        
        # التحقق من صحة الماك (يجب أن يكون بصيغة صالحة)
        if [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ] || [ ${#mac} -lt 10 ]; then
            log_message "تخطي جهاز غير صالح: $phone - MAC: $mac"
            continue
        fi
        
        # إضافة الماك إلى القائمة النشطة
        active_macs="$active_macs $mac"
        
        # فحص حالة المستخدم
        if [ "$status" != "active" ] && [ "$status" != "gift" ]; then
            # مستخدم محظور أو منتهي - قطع النت
            block_device "$mac"
            log_message "المستخدم $phone ($mac) بحالة $status - تم الحظر"
            
        elif [ "$(echo "$remaining <= 0" | bc 2>/dev/null)" -eq 1 ] 2>/dev/null; then
            # رصيد منتهي - قطع النت
            block_device "$mac"
            log_message "المستخدم $phone ($mac) رصيده منتهي ($remaining GB) - تم الحظر"
            
            # تحديث الحالة في Firebase (اختياري)
            curl -s -X PATCH -d '{"status":"critical"}' "https://sarhan-net-70a77-default-rtdb.firebaseio.com/active_users/$phone.json" 2>/dev/null
            
        else
            # مستخدم نشط - فتح النت وتطبيق السرعة
            allow_device "$mac"
            apply_speed_limit "$mac" "$speed_down" "$speed_up"
            log_message "المستخدم $phone ($mac) نشط - تم فتح النت بسرعة ${speed_down}Mbps/${speed_up}Mbps"
        fi
    done
    
    log_message "انتهت مزامنة الشبكة"
    rm -f "$LOCK_FILE"
}

# سياسة القاعدة الافتراضية - أغلق النت على الكل أولاً
set_default_policy() {
    log_message "تطبيق السياسة الافتراضية (حظر الكل أولاً)..."
    
    # حظر الكل في iptables
    iptables -P FORWARD DROP 2>/dev/null
    
    # السماح بالاتصالات القائمة
    iptables -I FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    
    # السماح للراوتر نفسه
    iptables -I FORWARD -i lo -j ACCEPT 2>/dev/null
    iptables -I FORWARD -o lo -j ACCEPT 2>/dev/null
    
    log_message "تم تطبيق السياسة الافتراضية - حظر الكل، ثم السماح للمستخدمين النشطين فقط"
}

# التشغيل الرئيسي
main() {
    log_message "======================"
    log_message "بدء تشغيل سكريبت السرحان NET"
    log_message "======================"
    
    # التحقق من dependencies
    check_dependencies
    
    # تنظيف القواعد القديمة
    cleanup_rules
    
    # تطبيق السياسة الافتراضية
    set_default_policy
    
    # تشغيل المزامنة فوراً
    sync_network
    
    # التشغيل الدوري كل دقيقتين (لتقليل استهلاك المعالج)
    while true; do
        sleep 120
        sync_network
    done
}

# تشغيل السكريبت
main