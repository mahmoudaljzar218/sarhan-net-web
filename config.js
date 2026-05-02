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
    ahmed: "201068222773",
    mahmoud: "201013959433"
};

// ========== عنوان فورتي جيت ==========
const FORTIGATE_IP = "192.168.137.116";
const FORTIGATE_PORT = "443";
const FORTIGATE_PROTOCOL = "https";

const DEFAULT_FORTIGATE_URL = `${FORTIGATE_PROTOCOL}://${FORTIGATE_IP}:${FORTIGATE_PORT}/fgtauth`;
const DEFAULT_LOGOUT_URL = `${FORTIGATE_PROTOCOL}://${FORTIGATE_IP}:${FORTIGATE_PORT}/logout`;

// ========== تهيئة Firebase ==========
if (typeof firebase !== 'undefined' && !firebase.apps.length) {
    firebase.initializeApp(FIREBASE_CONFIG);
}
const database = firebase.database();

function formatPhoneNumber(rawPhone) {
    if (!rawPhone) return "";
    let phone = rawPhone.toString().trim();
    phone = phone.replace(/\D/g, '');
    if (phone.startsWith('0')) phone = '20' + phone.substring(1);
    else if (phone.startsWith('1')) phone = '20' + phone;
    else if (!phone.startsWith('20')) phone = '20' + phone;
    return phone;
}

function saveFortiGateData(magic, postUrl) {
    if (magic) {
        sessionStorage.setItem('fgt_magic', magic);
        localStorage.setItem('saved_fgt_magic', magic);
    }
    if (postUrl) {
        sessionStorage.setItem('fgt_post', postUrl);
    }
}

function getFortiGateData() {
    return {
        magic: sessionStorage.getItem('fgt_magic') || localStorage.getItem('saved_fgt_magic'),
        postUrl: sessionStorage.getItem('fgt_post') || DEFAULT_FORTIGATE_URL
    };
}

function clearFortiGateData() {
    sessionStorage.removeItem('fgt_magic');
    sessionStorage.removeItem('fgt_post');
}

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

if (typeof module !== 'undefined' && module.exports) {
    module.exports = { 
        formatPhoneNumber, 
        sendTelegramText, 
        sendTelegramPhoto, 
        database,
        saveFortiGateData,
        getFortiGateData,
        clearFortiGateData,
        DEFAULT_FORTIGATE_URL,
        DEFAULT_LOGOUT_URL
    };
}
