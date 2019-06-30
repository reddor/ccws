/* basic unicode tests: filename, logging and sending/receiving */

var unicodeString = "Unicode 😎🤣✅✅ 翻譯錯誤";
console.log("Test: ", unicodeString);

handler.onConnect = function(client) {
	client.send(unicodeString);
};

handler.onData = function(client, data) {
	client.send(data === unicodeString ? "OK" : "FAIL");
	client.disconnect();
};

handler.onRequest = function(client) {
	client.send(unicodeString);
	client.disconnect();
};

var g = new GlobalEventListener('Test', 'Unicode'); g.addEventListener("ping", e => { g.globalDispatch("pong", "Unicode 😎 Test")});
