# ccws - ChakraCore powered WebSocket Server 

ccws is a lightweight linux-only web(socket)-server. It is the spiritual successor to my previous project [besenws](http://github.com/reddor/besenws) and currently under heavy construction. Under _no way_ it is encouraged to use this software in a productive or public environment.

It is made possible with
* [FreePascal](https://freepascal.org)
* [ChakraCore](https://github.com/microsoft/chakracore) & [ChakraCore-delphi](https://github.com/tondrej/chakracore-delphi)
* [Arat Synapse](http://www.ararat.cz/synapse/doku.php/start)

## Building
Checkout with submodules. Build using Lazarus (or lazbuild), or fpc itself if you manage to figure out the required parameters.
libChakraCore.so must be placed in /lib and can be obtained [here](https://github.com/Microsoft/ChakraCore/releases/tag/v1.11.10)

## Running
ccws will fork to the background and run as a service by default. Parameter `-debug` will keep it in foreground.
It runs just fine in Windows Subsystem For Linux (WSL)!

## Usage
ccws is organized in sites, which can be bound to one or more hosts - configuration is done in settings.js, which is worth to look at.
A site can host one or more websocket scripts which are bound to a specific endpoint. Each script runs in its own context and thread. The global `handler` object has different callbacks that you should implement:

| callback | signature | Description |
| -------- | --------- | ----------- |
| `handler.onConnect` | `function(client)` | Fired when a new websocket client connects. |
| `handler.onData` | `function(client, data)` | Fired when a websocket packet is received from a client. |
| `handler.onDisconnect` | `function(client)` | Fired when a websocket client is disconnected. |
| `handler.onRequest` | `function(client)` | Fired when a regular http request is made. The connection remains open and no response is sent until `client.disconnect()` is called. |

The `client` object implements various methods and properties for an existing connection:

| method/property | Description |
| --------------- | ----------- |
| `send(data)`    | sends a websocket packet to the client |
| `disconnect()`  | disconnects the client |
| `getHeader(key)`| returns an entry from the request header |
| `redirect(url)` | redirects a http request to the specified url |
| `host`          | the client ip address. read-only. |
| `lag`           | current lag of the websocket connection. only updated during idle pings. read-only. |
| `postData`      | data from an eventual POST request (http request only). read-only. |
| `pingTime`      | websocket ping interval. Sent after x ms of idle time |
| `maxPongTime`   | websocket ping time-out value. clients who fail to respond in time will be disconnected (this is handled by the websocket protocol, no client implementation is required) |
| `mimeType`      | the mime type for a http response. defaults to text/html |
| `returnType`    | the http response message. defaults to 200 OK |
| `parameter`     | the URI request parameter |

Further documentation and implementation details is still work in progress and subject to change. 

## Web Server
ccws can also serve static files, but you're encouraged to use a different webserver for this purpose, and use a reverse ssl proxy to only expose selected endpoints. 
