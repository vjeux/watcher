
 * You have a lot of CoffeeScript, Haml, SASS ... files and you want them to be automatically compiled when you save.
 * You don't want a full "IDE" like [LiveReload](http://livereload.com/) [CodeKit](http://incident57.com/codekit/) or [Compass](http://compass.handlino.com/).

Install
=======

```bash
npm install -g watcher
```

Command Line
============

Output in the same folder

```
watcher src/
```

Output in the bin/ folder

```
watcher -o bin/ src/
```

Watch a single file

```
watcher src/application.coffee
```

Output Example
==============

Let's start the watcher, it compiles everything it finds.

```
22:36:30 - compiled src/index.haml
22:36:30 - compiled src/soulver.coffee
22:36:30 - compiled src/soulver.less
```

Oops, we made an error:

```
22:36:56 - compiled src/soulver.coffee
bin/soulver.js: Error: Parse error on line 2: Unexpected '''
    at Object.parseError (/usr/local/lib/node_modules/coffee-script/lib/coffee-script/parser.js:470:11)
    at Object.parse (/usr/local/lib/node_modules/coffee-script/lib/coffee-script/parser.js:546:22)
    at Object.compile (/usr/local/lib/node_modules/coffee-script/lib/coffee-script/coffee-script.js:40:22)
    at /usr/local/lib/node_modules/coffee-script/lib/coffee-script/command.js:140:33
    at Socket.<anonymous> (/usr/local/lib/node_modules/coffee-script/lib/coffee-script/command.js:167:14)
    at Socket.emit (events.js:64:17)
    at Pipe.onread (net.js:348:51)
```

We save again and it goes back in order :)

```
22:37:15 - compiled src/soulver.coffee
```