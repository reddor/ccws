handler.onRequest = function(client) {
	try {
		console.log("Got request for " + client.parameter);
		var r = new XMLHttpRequest();
		let x = client.parameter.split("/");
		// lets not be a generic proxy
		if ((x[1] != "/dummy.txt") || x.length != 2) {
			client.disconnect();
			return;
		}
	        r.open("GET", client.parameter);
	        r.onreadystatechange = function(e) {
			if(r.readyState == 4) {
				client.send(r.responseText);
				client.disconnect();
			}
		};
	        r.onerror = function(e) {
			client.send("FAIL: XMLHttpRequest fired error " + e);
			client.disconnect();
		}
	        r.send();
	} catch(e) {
		client.send("FAIL: " + e.message);
		client.disconnect();
	}
}
