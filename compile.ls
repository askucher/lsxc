require! {
    \fs
    \through
    \require-ls
    \browserify-incremental : \browserifyInc
    \livescript
    \browserify
    \xtend
    \node-sass : \sassc
    \node-watch : \watch
    \fix-indents
    \chalk : { red, yellow, gray, green }
    \express
    \vm
    \clean-css
    \html-minifier : { minify } 
    \uglify-js : UglifyJS
    \./monadify.ls
    \reactify-ls : \reactify
}


basedir = process.cwd!
compileddir = "#{basedir}/.compiled"
ssrdappdir = "#{basedir}/.compiled-ssr"

minify-html = (it)-> it 
minify-js = (it)-> UglifyJS.minify(it).code
minify-css = (css)-> 
  new clean-css({}).minify(css).styles

base-title = (colored, symbol, text)-->
  text = "[#{colored symbol}] #{colored text}"
  max = 40 - text.length
  if max <= 0 then text
  else text + [0 to max].map(-> " ").join('')

title = base-title green, "✓"
error = base-title red, "x"
warn  = base-title yellow, "!"


ensure-dir = (dir)->
    fs.mkdir-sync(dir) if not fs.exists-sync(dir)

ensure-dir compileddir
ensure-dir ssrdappdir

save = (file, content)->
    save-origin "#{compileddir}/#{file}" , content

get-parent = (file)->
  arr = file.split(\/)
  arr.pop!
  arr.join(\/)

save-origin = (file, content)->
    console.log "#{title 'save'} #{file}"
    fs.write-file-sync file , content
save-ssr = (file, content)->
    target = "#{ssrdappdir}/#{file}"
    ensure-dir get-parent target
    save-origin target , content


setup-watch = (commander)->
    return if setup-watch.init
    console.log warn "watcher started..."
    setup-watch.init = yes
    watcher = watch do
        * basedir
        * recursive: yes
          filter: (name)->
             !/(node_modules|\.git)/.test(name)
        * (evt, name)->
             return if setup-watch.disabled
             console.log "#{warn 'changed'} #name"
             setup-watch.disabled = yes
             #watcher.close!
             err <-! compile commander
             <-! set-timeout _, 500
             setup-watch.disabled = no
server-start = (commander)->
  return if server-start.init
  server-start.init = yes
  app = express!
  app.use(express.static(compileddir)) 
  port =   if commander.nodestart is yes then 8080 else commander.nodestart
  start = ->
    app.listen port, ->
      console.log("#{warn 'node started'} port #{port}")
  script = new vm.Script("(#{start.to-string!})()" )
  context = new vm.create-context( { port, app, console, warn } )
  script.run-in-context context
  port
  
compile-file = (input, data)->
  console.log "#{title 'compile'} #{input}" 
  code = reactify data
  state =
    js: null
  try 
    state.js = livescript.compile monadify code.ls
  catch err 
    state.err = err.message
    errorline = err.message.match(/line ([0-9]+)/).1 ? 0
    
    lines = code.ls.split(\\n)
    for index of lines 
       if index is errorline
         lines[index] = lines[index] + "       <<< #{red err.message}"
       else 
         lines[index] = gray lines[index]
    console.log ([] ++ lines).join(\\n)
  #target = input.replace(/\[^\/]+.ls/,\.js)
  #save target, state.js
  { code.ls, code.sass, state.js, state.err}
apply-variables = (text, variables)->
    apply-variable = (text, name)->
        text.split("<#{name}/>").join(variables[name])
    Object.keys(variables).reduce(apply-variable, text) 
compile = (commander, cb)->
    if commander.jsify? 
      filename = commander.jsify.replace /\.ls$/,''
      result = livescript.compile monadify reactify(fs.read-file-sync(filename + ".ls", 'utf8')).ls
      return fs.write-file-sync(filename + ".js", result)
    save-ssr-resource = (file, content)->
      return if commander.ssr isnt yes
      save-ssr file.replace(get-parent(basedir) + "/", ""), content
    console.log "----------------------"
    cb2 = (err, data)->
      if err?
         console.log "#{red 'Error'} err"
      cb? err, data
    file = commander.compile
    sass-cache = do
      path = "#{compileddir}/#{file}.sass.cache"
      save: (obj)->
         fs.write-file-sync(path, JSON.stringify(obj))
      load: ->
         return {} if not fs.exists-sync(path)
         JSON.parse fs.read-file-sync(path).to-string(\utf8)
    sass-c = sass-cache.load!
    #return if file.index-of('.ls') is -1
    return cb2 'File is required' if not file?
    filename = file.replace /\.ls$/,''
    bundle = if commander.bundle is yes then \bundle else commander.bundle
    bundle-js =  "#{filename}-#{bundle}.js"
    bundle-css = "#{filename}-#{bundle}.css"
    html = if commander.html is yes then \index else commander.html
    bundle-html = "#{filename}-#{html}.html"
    sass = if commander.sass is yes then \style else commander.sass
    compilesass = if commander.compilesass is yes then \style else commander.compilesass
    
       
    
    sass-c[commander.compile] = sass-c[commander.compile] ? {}
    make-bundle = (file, callback)->
        console.log "#{title 'start main file'} #file"
        options = 
            basedir: basedir
            paths: ["#{basedir}/node_modules"]
            debug: no 
            commondir: no
            entries: [file]
        b = browserify xtend(browserify-inc.args, options)
        b.transform (file) ->
          #json = file.match(/([a-z-0-9_]+)\.json$/)?1
          #js = file.match(/([a-z-0-9_]+)\.js$/)?1
          filename = file.match(/([a-z-0-9_]+)\.ls$/)?1
          data = ''
          write = (buf) -> data += buf
          
          end = ->
            t = @
            send = (data)->
                t.queue data
                t.queue null
            save-ssr-resource file, data
            return send data if not filename?
            code =
                compile-file file, data
            save-ssr-resource file, code.ls
            if sass?
              save "#{filename}.sass", code.sass
            if commander.fixindents
              indented = fix-indents data
              if data isnt indented
                 console.log "#{title 'fix indents'} #file"
                 save-origin file, indented
            if compilesass?
              console.log "#{title 'compile'} #{filename}.sass"
              if code.sass.length > 0
                sass-conf =
                    data: code.sass
                    indented-syntax: yes
                try
                  sass-c[commander.compile][file] = sassc.render-sync(sass-conf).css.to-string(\utf8)
                catch err
                  console.error "#{error 'err compile sass'}  #{yellow err.message}"
              else 
                sass-c[commander.compile][file] = ""
            save "#{filename}.js", code.js
            send code.js
          through write, end
        browserify-inc b, { cache-file:  "#{compileddir}/#{file}.cache" }
        bundle = b.bundle!
        string = ""
        bundle.on \data, (data)->
          string += data.to-string!
        bundle.on \error, (err)->
          console.log "#{ error 'bundle err' } #{err.message ? err}"
        _ <-! bundle.on \end
        compiled-sass = sass-c[commander.compile]
        result =
          css: Object.keys(compiled-sass).map(-> compiled-sass[it]).join(\\n)
          js: string
        sass-cache.save sass-c
        callback null, result
    if commander.compile? and not commander.bundle?
      filename = commander.compile.match(/([a-z-0-9_]+)\.ls$/)?1
      return cb "expected ls file" if not filename?
      err, data <- fs.read-file commander.compile, 'utf8'
      return cb err if err?
      err, content <- compile-file filename, data
      return cb err if err?
      err, data <- fs.write-file filename.replace(/\.ls$/, '.js'), content
      return cb err if err?
      cb null
    if commander.bundle?
      err, bundlec <-! make-bundle file
      return cb2 err if err? 
      #if commander.javascrypt
      #   bundlec.js = encrypt bundlec.js
      if commander.minify
         bundlec.js = minify-js bundlec.js
         bundlec.css = minify-css bundlec.css
      if not commander.putinhtml?
         save bundle-js, bundlec.js
      if compilesass? and not commander.putinhtml?
         save bundle-css, bundlec.css
      
      dynamicCSS =  | commander.putinhtml => """<style>#{bundlec.css}</style>"""
                    | _ => """ <link rel="stylesheet" type="text/css" href="./#{bundle-css}">  """
      dynamicHTML = | commander.putinhtml => """<script>#{bundlec.js}</script>"""
                    | _ => """<script type="text/javascript" src="./#{bundle-js}"></script>"""
      if commander.html?
          default-template = '''
          <!DOCTYPE html>
          <html lang="en-us">
            <head>
             <meta charset="utf-8">
             <title>loading...</title>
             <dynamicCSS/>
            </head>
            <dynamicHTML/>
          </html>
          '''
          current-template = 
            | commander.template? => fs.read-file-sync commander.template, \utf8
            | _ => default-template
          html = apply-variables current-template, { dynamicCSS, dynamicHTML }
          result-html =
            | commander.minify => minify-html html
            | _ => html
          save bundle-html, result-html
      if commander.nodestart?
         server-start commander
      if commander.watch
         setup-watch commander
      cb2 null, \success
module.exports = compile
