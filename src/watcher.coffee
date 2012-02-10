# The `coffee` utility. Handles command-line compilation of CoffeeScript
# into various forms: saved into `.js` files or printed to stdout, piped to
# [JavaScript Lint](http://javascriptlint.com/) or recompiled every time the source is
# saved, printed as a token stream or as the syntax tree, or launch an
# interactive REPL.

# External dependencies.
fs             = require 'fs'
path           = require 'path'
optparse       = require './optparse'
handlers       = require './handlers'
{spawn, exec}  = require 'child_process'
{EventEmitter} = require 'events'

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'

# The help banner that is printed when `coffee` is called without arguments.
BANNER = '''
	Usage: watcher [options] path/to/file

	--- Examples ---

	Output in the same folder
	  watcher src/

	Output in the bin/ folder
	  watcher -o bin/ src/

	Watch a single file
	  watcher src/application.coffee

	--- Options ---
				 '''

# The list of all the valid option flags that `coffee` knows how to handle.
SWITCHES = [
	['-h', '--help',            'display this help message']
#	['-j', '--join [FILE]',     'concatenate the source CoffeeScript before compiling']
	['-o', '--output [DIR]',    'set the output directory for compiled JavaScript']
]

# Top-level objects shared by all the functions.
opts         = {}
sources      = []
sourceCode   = []
notSources   = {}
watchers     = {}
optionParser = null

# Run `coffee` by parsing passed options and determining what action to take.
# Many flags cause us to divert before compiling anything. Flags passed after
# `--` will be passed verbatim to your script as arguments in `process.argv`
exports.run = ->
	parseOptions()
	return usage() if opts.help or sources.length == 0
	if !fs.watch
		printWarn "The --watch feature depends on Node v0.6.0+. You are running #{process.version}."
	for source in sources
		compilePath source, yes, path.normalize source

# Compile a path, which could be a script or a directory. If a directory
# is passed, recursively compile all '.coffee' extension source files in it
# and all subdirectories.
compilePath = (source, topLevel, base) ->
	fs.stat source, (err, stats) ->
		throw err if err and err.code isnt 'ENOENT'
		if err?.code is 'ENOENT'
			if topLevel and path.extname(source)[1...] not of handlers
				# Not sure what it does and how to replace the '.coffee'
				source = sources[sources.indexOf(source)] = "#{source}.coffee"
				return compilePath source, topLevel, base
			if topLevel
				console.error "File not found: #{source}"
				process.exit 1
			return
		if stats.isDirectory()
			watchDir source, base
			fs.readdir source, (err, files) ->
				throw err if err and err.code isnt 'ENOENT'
				return if err?.code is 'ENOENT'
				files = files.map (file) -> path.join source, file
				index = sources.indexOf source
				sources[index..index] = files
				sourceCode[index..index] = files.map -> null
				compilePath file, no, base for file in files
		else if topLevel or path.extname(source)[1...] of handlers
			watch source, base
			fs.readFile source, (err, code) ->
				throw err if err and err.code isnt 'ENOENT'
				return if err?.code is 'ENOENT'
				compileScript(source, code.toString(), base)
		else
			notSources[source] = yes
			removeSource source, base


# Compile a single source script, containing the given code, according to the
# requested options. If evaluating the script directly sets `__filename`,
# `__dirname` and `module.filename` to be correct relative to the script's path.
compileScript = (file, input, base) ->
	writeJs file, input, base

# If all of the source files are done being read, concatenate and compile
# them together.
joinTimeout = null
compileJoin = ->
	return unless opts.join
	unless sourceCode.some((code) -> code is null)
		clearTimeout joinTimeout
		joinTimeout = wait 100, ->
			compileScript opts.join, sourceCode.join('\n'), opts.join

# Load files that are to-be-required before compilation occurs.
loadRequires = ->
	realFilename = module.filename
	module.filename = '.'
	require req for req in opts.require
	module.filename = realFilename

# Watch a source CoffeeScript file using `fs.watch`, recompiling it every
# time the file is updated. May be used in combination with other options,
# such as `--lint` or `--print`.
watch = (source, base) ->

	prevStats = null
	compileTimeout = null

	watchErr = (e) ->
		if e.code is 'ENOENT'
			return if sources.indexOf(source) is -1
			removeSource source, base, yes
			compileJoin()
		else throw e

	compile = ->
		clearTimeout compileTimeout
		compileTimeout = wait 125, ->
			fs.stat source, (err, stats) ->
				return watchErr err if err
				return if prevStats and (stats.size is prevStats.size and
					stats.mtime.getTime() is prevStats.mtime.getTime())
				prevStats = stats
				fs.readFile source, (err, code) ->
					return watchErr err if err
					compileScript(source, code.toString(), base)

	watchErr = (e) ->
		throw e unless e.code is 'ENOENT'
		removeSource source, base, yes
		compileJoin()

	try
		watcher = fs.watch source, callback = (event) ->
			if event is 'change'
				compile()
			else if event is 'rename'
				watcher.close()
				wait 25, ->
					compile()
					try
						watcher = fs.watch source, callback
					catch e
						watchErr e
	catch e
		watchErr e


# Watch a directory of files for new additions.
watchDir = (source, base) ->
	readdirTimeout = null
	try
		watcher = fs.watch source, ->
			clearTimeout readdirTimeout
			readdirTimeout = wait 25, ->
				fs.readdir source, (err, files) ->
					if err
						throw err unless err.code is 'ENOENT'
						watcher.close()
						return unwatchDir source, base
					files = files.map (file) -> path.join source, file
					for file in files when not notSources[file]
						continue if sources.some (s) -> s.indexOf(file) >= 0
						sources.push file
						sourceCode.push null
						compilePath file, no, base
	catch e
		throw e unless e.code is 'ENOENT'

unwatchDir = (source, base) ->
	prevSources = sources.slice()
	toRemove = (file for file in sources when file.indexOf(source) >= 0)
	removeSource file, base, yes for file in toRemove
	return unless sources.some (s, i) -> prevSources[i] isnt s
	compileJoin()

# Remove a file from our source list, and source code cache. Optionally remove
# the compiled JS version as well.
removeSource = (source, base, removeJs) ->
	index = sources.indexOf source
	sources.splice index, 1
	sourceCode.splice index, 1
	if removeJs and not opts.join
		jsPath = outputPath source, base
		path.exists jsPath, (exists) ->
			if exists
				fs.unlink jsPath, (err) ->
					throw err if err and err.code isnt 'ENOENT'
					timeLog "removed #{source}"

# Get the corresponding output JavaScript path for a source file.
outputPath = (source, base) ->
	filename  = path.basename(source, path.extname(source))
	srcDir    = path.dirname source
	baseDir   = if base is '.' then srcDir else srcDir.substring base.length
	dir       = if opts.output then path.join opts.output, baseDir else srcDir
	path.join dir, filename

# Write out a JavaScript source file with the compiled code. By default, files
# are written out in `cwd` as `.js` files with the same name, but the output
# directory can be customized with `--output`.
writeJs = (source, js, base) ->
	ext = (path.extname source)[1...]
	jsPath = outputPath source, base
	jsDir  = path.dirname jsPath
	compile = ->
		handlers[ext] js, source, jsPath
		timeLog "compiled #{source}"
	path.exists jsDir, (exists) ->
		if exists then compile() else exec "mkdir -p #{jsDir}", compile

# Convenience for cleaner setTimeouts.
wait = (milliseconds, func) -> setTimeout func, milliseconds

# When watching scripts, it's useful to log changes with the timestamp.
timeLog = (message) ->
	console.log "#{(new Date).toLocaleTimeString()} - #{message}"

# Pipe compiled JS through JSLint (requires a working `jsl` command), printing
# any errors or warnings that arise.
lint = (file, js) ->
	printIt = (buffer) -> printLine file + ':\t' + buffer.toString().trim()
	conf = __dirname + '/../../extras/jsl.conf'
	jsl = spawn 'jsl', ['-nologo', '-stdin', '-conf', conf]
	jsl.stdout.on 'data', printIt
	jsl.stderr.on 'data', printIt
	jsl.stdin.write js
	jsl.stdin.end()

# Use the [OptionParser module](optparse.html) to extract all options from
# `process.argv` that are specified in `SWITCHES`.
parseOptions = ->
	optionParser  = new optparse.OptionParser SWITCHES, BANNER
	o = opts      = optionParser.parse process.argv.slice 2
	o.compile     or=  !!o.output
	o.run         = not (o.compile or o.print or o.lint)
	o.print       = !!  (o.print or (o.eval or o.stdio and o.compile))
	sources       = o.arguments
	sourceCode[i] = null for source, i in sources
	return

# Print the `--help` usage message and exit. Deprecated switches are not
# shown.
usage = ->
	printLine (new optparse.OptionParser SWITCHES, BANNER).help()
