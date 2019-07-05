
function testGlobalEvents(success, failure) {
    var r = new XMLHttpRequest();
	r.open("GET", "/test/globalevents");
	r.addEventListener("load", function(e) {
        r.responseText.indexOf("FAIL:") != 0 ? success(r.responseText) : failure(r.responseText);
        console.log(r.responseText);
	});
	r.addEventListener("error", function(e) {
		failure("XMLHttpRequest error");
	});
	r.send();
}

function testProcess(success, failure) {
    var r = new XMLHttpRequest();
	r.open("GET", "/test/process");
	r.addEventListener("load", function(e) {
        r.responseText.indexOf("FAIL:") != 0 ? success(r.responseText) : failure(r.responseText);
        console.log(r.responseText);
	});
	r.addEventListener("error", function(e) {
		failure("XMLHttpRequest error");
	});
	r.send();
}

function testEventListeners(success, failure) {
	let url = ((location.protocol == "https:") ? "wss" : "ws") + '://'+location.hostname+(location.port ? ':'+location.port: '') + "/test/eventlistener";
	let ws = new WebSocket(url);
	let gotsuccess = false;
	let msg;
	ws.onopen = function(e) {
		ws.send("OK");
	}
	ws.onmessage = function(e) {
		if (msg == "") msg = e.data;
		gotsuccess = (e.data === "OK");
	};
	ws.onclose = function(e) {
		gotsuccess ? success("That worked.") : failure(msg);
	};
	ws.onerror = function(e) {
		failure("websocket error");
	};
}
