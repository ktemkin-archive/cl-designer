exports.config =
  # See http://brunch.readthedocs.org/en/latest/config.html for documentation.
  files:
    javascripts:
      joinTo:
        'javascripts/app.js': /^(app.*\.coffee)|(app\/grammars.*\.js)$/

        'javascripts/vendor.js': /^vendor/
      order:
        before: []

    stylesheets:
      joinTo:
        'stylesheets/app.css': /^app.*styl/
        'stylesheets/vendor.css': /^vendor.*css/
      order:
        before: []
        after: []

    templates:
      joinTo: 'javascripts/templates.js'


  plugins:
    jade:
      options:
        pretty: yes

