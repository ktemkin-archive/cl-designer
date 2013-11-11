###
  
 [Hey, this is CoffeeScript! If you're looking for the original source,
  look in "file.coffee", not "file.js".]

 QuickLogic Combinational Logic Designer
 Copyright (c) Binghamton University,
 author: Kyle J. Temkin <ktemkin@binghamton.edu>

 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:

 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
###

{LogicEquation} = require 'lib/logic_equation'

class exports.QuickLogicApplication

  #
  # Perform the core JS start-up, once the window is ready.
  #
  constructor: (@editor_div, @sidebar, @toolbar, @file_form=null) ->
  
    # Create a basic data-store for the persistant features, like autosaving.
    @datastore = new Persist.Store('QuickLogic', {swf_path: 'flash/persist.swf'})

    # Sets up the local toolbar events.
    @set_up_toolbar()

    # Set up the "load file in place" event, which should trigger 
    # when a file is selected to be opened via the HTML5 file dialog.
    document.getElementById('fileOpen').onchange = @handle_file_selection
    document.getElementById('cancelOpen').addEventListener('click', @handle_cancel_open_click) 

    # Innitially, don't process any UI event.
    @active_ui_event = null

    # If we haven't seen this user before, show the help panel.
    @show_help() unless @datastore.get('seen')


  #
  # Sets up the handlers for all of the toolbar buttons.
  #
  set_up_toolbar: ->

    button_handlers =
      'btnNew':         @handle_new_click
      'btnOpen':        @handle_open_click
      #'btnSaveHTML5':   @handle_save_html5_click
      #'btnSavePNG':     @handle_save_png_click

    # Add each of the button handlers to their respective buttons.
    for id, handler of button_handlers
      document.getElementById(id).addEventListener('click', handler)
  
    # Create the flash-based download button, if Flash is supported.
    @set_up_download_button()


  #
  # Set up a better download experience, on systems that support Flash.
  # (The HTML5 download "API" currently doesn't allow a save dialog.)
  # 
  set_up_download_button: ->

    #Get a reference to the HTML5 save button we want to replace.
    download_button = document.getElementById('btnSaveHTML5')

    # If supported, create a better download button using Downloadify.
    downloadify_options =
      swf: 'flash/downloadify.swf'
      downloadImage: 'images/download.gif'
      width: download_button.offsetWidth
      height: download_button.offsetHeight
      append: true
      transparent: true
      filename: 'Design.eqs'
      data: => @editor.getValue()
    Downloadify.create('btnSave', downloadify_options)


  #
  # Show the help panel.
  #
  show_help: ->

    # Show the help panel...
    helpPanel = document.getElementById('helpPanel')
    @set_element_opacity(helpPanel, 1)

    # ... and mark it as seen.
    @datastore.set('seen', true)


  #
  # Start the Application.
  # This should be called once all of the preliminary setup is complete,
  # and the application is ready to handle events.
  #
  run: =>

    # Attempt to fetch data regarding the last design, if it exists.
    last_design = @datastore.get('autosave')

    # Create the base editor, which is the primary user interface.
    @editor = ace.edit(@editor_div)
    @editor.setValue(last_design)

    @set_up_editor()

  #
  # Sets up the main editor, attaching the events necessary
  # for the application to run.
  #
  set_up_editor: =>

    #Update the editor's display each time the editor is changed.
    @editor.on('change', @update_side_display)


  #
  # Handles updating of the side panel.
  #
  update_side_display: =>

    #DEBUG ONLY
    try
      expression = new LogicEquation(@editor.getValue())
      @render_truth_table(expression.truth_table())
    catch error
      console.log error


  #
  # Renders a truth table in the right-most pane.
  #
  render_truth_table: (truth_table) =>
   
    #Start an array of HTML fragments.
    #(JavaScript strings are immutable, so string concatination
    # is a heavy operation. We'll use an array, and join the 
    # segments later.)
    html = []

    #Add a header labeling each of the inputs.
    #TODO: Support multiple output functions?
    html.push("<table class=\"truthtable\"><thead><tr>")
    html.push("<th class=\"input\">#{input}</th>") for input in truth_table.inputs
    html.push("<th class=\"output\">#{truth_table.output}</th>")
    html.push("</tr></thead><tbody>")


    #Iterate over each of the rows in the given truth table.
    for row in truth_table.rows

      #Break the truth table into its inputs and outputs.
      [inputs, output] = row

      #Output each of the inputs and outputs.
      html.push("<tr>")
      html.push("<td class=\"input\">#{inputs[input]}</td>") for input in truth_table.inputs
      html.push("<td class=\"output\">#{output}</td>")
      html.push("</tr>")


    #And end the table.
    html.push("</tbody></table>")

    #Push the content into the side panel.
    @set_side_panel_content(html.join(''))


  #
  # Sets the HTML content of the side panel;
  # automatically adjusting its size, if necessary.
  #
  set_side_panel_content: (content) =>

    #Adjust the raw content of the side-panel bar.
    document.getElementById("sidebar_content").innerHTML = content

        




  #
  # Handles a click on the new button.
  #
  handle_new_click: =>
    @editor.setValue('')


  #
  # Handles the "Save" button; saves an equation file using a Data URI.
  # This method is not preferred, but will be used if Flash cannot be found.
  #
  handle_save_html5_click: =>
    
    #get a serialization of the FSM's state, for saving
    content = @designer.serialize()
    
    #convert it to a data URI
    uri_content = 'data:application/x-eqs,' + encodeURIComponent(content)
    
    #and ask the user's browser to download it
    document.location.href = uri_content

  #
  # TODO: Handle schematic generation!
  #

  #
  # Handles clicks of the "open" toolbar button.
  #
  handle_open_click: =>

    # If we have access to the HTML5 file api
    if FileReader?
      document.getElementById('fileOpen').click()
    else
      @show_file_open_fallback()


  #
  # Fallback to server-side file opening, as the current browser
  # doesn't support it.
  #
  show_file_open_fallback: ->
    @set_element_opacity(@file_form, .95)


  #
  # Sets the file dialog's opacity.
  #
  set_element_opacity: (element, value, autohide=true) ->
    return unless element?

    # Set the opacity of the file dialog...
    element.style.opacity = value 
    element.style.filter  = "alpha(opacity=#{value * 100})"

    #If autohide is on, hide the form if it's not visible.
    #(This prevent it from being made interactable)
    return unless autohide

    @schedule_ui_event =>
      element.style.display = if value > 0 then 'block' else 'none'



  #
  # Handles cancellation of the file open dialog.
  #
  handle_cancel_open_click: (e) =>
    @set_element_opacity(@file_form, 0)


  #
  # Handle clicks on the "help" button.
  #
  handle_help_click: (e) =>
    helpPanel = document.getElementById('helpPanel')
    @set_element_opacity(helpPanel, 1)


  #
  # Handles clicks on the "dismiss help" button.
  #
  handle_dismiss_help_click: (e) =>
    helpPanel = document.getElementById('helpPanel')
    @set_element_opacity(helpPanel, 0)

  #
  # Schedule a UI event, displacing any existing UI event.
  #
  schedule_ui_event: (event, timeout=100) =>
    clearTimeout(@active_ui_event) if @active_ui_event?
    setTimeout(event, timeout)


  
  #
  # Handle selection of a file in 
  # 
  handle_file_selection: (e) =>

    # If we don't have the HTML5 file api, don't handle this event.
    return unless FileReader?

    # Return unless the user has selected exactly one file.
    return unless e?.target?.files?.length == 1

    # Open the relevant file.
    @load_from_file(e.target.files[0])

    #TODO: De-select the given file?


  #
  # Loads a set of equations from an equation file.
  #
  load_from_file: (file) =>

    #create a new FileReader, and instruct it to
    # 1) read the file's contents, and
    # 2) pass the result to the text editor
    reader = new FileReader()
    reader.onload = (file) => @editor.setValue(file.target.result)
    reader.readAsText(file)




