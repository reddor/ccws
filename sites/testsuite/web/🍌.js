var unicodeString = "Unicode 😎🤣✅✅ 翻譯錯誤";
var unicodeTestState = "not run";
var unicodeUrl = "/test/unicode😎";

function testUnicodeRequest(success, failure) {
	var r = new XMLHttpRequest();
	r.open("GET", unicodeUrl);
	// seems this is illegal after all
	//r.setRequestHeader("X-Unicode", "🍕");
	r.addEventListener("load", function(e) {
		r.responseText === unicodeString ? success() : failure("got "+r.responseText);
	});
	r.addEventListener("error", function(e) {
		failure("XMLHttpRequest error");
	});
	r.send();
}

function testUnicodeWebsocket(success, failure) {
	var url = ((location.protocol == "https:") ? "wss" : "ws") + '://'+location.hostname+(location.port ? ':'+location.port: '') + unicodeUrl;
	var ws = new WebSocket(url);
	var gotmessage = false;
	var gotsuccess = false;
	ws.onmessage = function(e) {
		if(gotmessage) {
			gotsuccess = gotsuccess && (e.data === "OK");
		} else {
			gotmessage = true;
			gotsuccess = e.data === unicodeString;
			ws.send(e.data);
		}
	};
	ws.onclose = function(e) {
		gotsuccess ? success() : failure(gotmessage ? "message broken in transit" : "no message returned");
	};
	ws.onerror = function(e) {
		failure("websocket error");
	};
}
