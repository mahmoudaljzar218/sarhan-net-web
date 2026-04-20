// ========== إعدادات Firebase ==========
const FIREBASE_CONFIG = {
    apiKey: "AIzaSyC1FAd4_3s4lkrbMmyv09eZFfEhtrqeiDU",
    databaseURL: "https://sarhan-net-70a77-default-rtdb.firebaseio.com",
    projectId: "sarhan-net-70a77"
};

// ========== إعدادات Telegram ==========
const TELEGRAM_BOT_TOKEN = "8776420009:AAFk_OzHmZ3fYRDVh5FoBdKRjJHy1nsijr0";
const TELEGRAM_CHAT_ID = "6496332668";

// ========== أرقام الإدارة للواتساب ==========
const ADMIN_PHONES = {
    ahmed: "201068222773",   // أحمد السرحان (المالية)
    mahmoud: "201013959433"  // محمود السرحان (البرمجة)
};

// ========== تهيئة Firebase (مرة واحدة) ==========
if (typeof firebase !== 'undefined' && !firebase.apps.length) {
    firebase.initializeApp(FIREBASE_CONFIG);
}
const database = firebase.database();

// ========== دوال مساعدة ==========
function formatPhoneNumber(rawPhone) {
    if (!rawPhone) return "";
    let phone = rawPhone.toString().trim();
    phone = phone.replace(/\D/g, '');
    if (phone.startsWith('0')) phone = '20' + phone.substring(1);
    else if (phone.startsWith('1')) phone = '20' + phone;
    else if (!phone.startsWith('20')) phone = '20' + phone;
    return phone;
}

// ========== دوال Telegram ==========
function sendTelegramText(message) {
    const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`;
    return fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: TELEGRAM_CHAT_ID, text: message, parse_mode: 'HTML' })
    });
}

function sendTelegramPhoto(photoFile, caption) {
    const formData = new FormData();
    formData.append('chat_id', TELEGRAM_CHAT_ID);
    formData.append('photo', photoFile);
    formData.append('caption', caption);
    return fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto`, { method: 'POST', body: formData });
}

// ========== دوال إضافية للتكامل ==========
function sendToBothAdmins(message) {
    // إرسال للتيليجرام
    sendTelegramText(message);
    
    // يمكن إضافة إرسال للواتساب للأدمنين هنا
    console.log("تم إرسال الإشعار للأدمنين:", message);
}

function logActivity(action, details) {
    const logRef = database.ref('logs/' + Date.now());
    logRef.set({
        action: action,
        details: details,
        timestamp: new Date().toLocaleString(),
        userAgent: navigator.userAgent
    });
}

// تصدير الدوال للاستخدام في الملفات الأخرى
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { formatPhoneNumber, sendTelegramText, sendTelegramPhoto, sendToBothAdmins, logActivity, database };
}