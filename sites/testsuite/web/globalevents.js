
function testGlobalEvents(success, failure) {
    var r = new XMLHttpRequest();
	r.open("GET", "/test/globalevents");
	r.addEventListener("load", function(e) {
        r.responseText.indexOf("FAIL:") != 0 ? success() : failure("got "+r.responseText);
        console.log(r.responseText);
	});
	r.addEventListener("error", function(e) {
		failure("XMLHttpRequest error");
	});
	r.send();
}
