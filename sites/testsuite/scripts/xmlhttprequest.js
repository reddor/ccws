handler.onRequest = function(client) {
	try {
	        var r = new XMLHttpRequest();
	        r.open("GET", "http://raw.githubusercontent.com/reddor/ccws/master/README.md");
	        r.onreadystatechange = function(e) {
			if(e.readyState == 4) {
				client.send(e.responseText);
				client.disconnect();
			}
		};
	        r.onerror = function(e) {
			client.send("FAIL: XMLHttpRequest fired error");
			client.disconnect();
		}
	        r.send();
	} catch(e) {
		client.send("FAIL: " + e.message);
		client.disconnect();
	}
}
