
fs = require 'fs'
{spawn, exec} = require 'child_process'

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'

run = (command, content, file) ->
	[prog, args...] = command.split ' '
	proc = spawn prog, args

	if content? and file?
		stream = fs.createWriteStream file
		proc.stdout.pipe stream
		proc.stderr.on 'data', (buffer) ->
			printWarn file + ':\t' + buffer.toString().trim()

		proc.stdin.write content
	proc.stdin.end()

module.exports =
# JS
	coffee: (content, inputPath, outputPath) ->
		run 'coffee --stdio --compile', content, outputPath + '.js'

	jison: (content, inputPath, outputPath) ->
		run 'jison ' + inputPath + ' -o ' + outputPath + '.js'

# CSS
	scss: (content, inputPath, outputPath) ->
		run 'sass --stdin --scss', content, outputPath + '.css'

	sass: (content, inputPath, outputPath) ->
		run 'sass --stdin', content, outputPath + '.css'

	less: (content, inputPath, outputPath) ->
		run 'lessc -', content, outputPath + '.css'

	styl: (content, inputPath, outputPath) ->
		run 'stylus', content, outputPath + '.css'

# HTML
	haml: (content, inputPath, outputPath) ->
		run 'haml --stdin', content, outputPath + '.html'

	jade: (content, inputPath, outputPath) ->
		run 'jade', content, outputPath + '.html'
