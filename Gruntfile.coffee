module.exports = (grunt) ->
  grunt.initConfig
    pkg: grunt.file.readJSON("package.json")
    coffee:
      compile:
        files:
          'bucky.js': 'bucky.coffee'
          'spec/bucky.spec.js': 'spec/bucky.spec.coffee'

    watch:
      coffee:
        files: ['bucky.coffee', 'spec/bucky.spec.coffee']
        tasks: ["coffee", "uglify"]

    uglify:
      options:
        banner: "/*! <%= pkg.name %> <%= pkg.version %> */\n"

      dist:
        src: 'bucky.js'
        dest: 'bucky.min.js'

    jasmine:
      options:
        specs: ['spec/bucky.spec.js']
      src: [
        'spec/vendor/jquery-1.10.2/jquery.js',
        'spec/vendor/underscore-1.5.2/underscore.js',
        'spec/vendor/backbone-1.0.0/backbone.js',
        'spec/vendor/sinon-1.7.3/sinon.js',
        'bucky.js'
      ]

  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-jasmine'

  grunt.registerTask 'default', ['coffee', 'uglify']
  grunt.registerTask 'build', ['coffee', 'uglify', 'jasmine']
  grunt.registerTask 'test', ['coffee', 'uglify', 'jasmine']
