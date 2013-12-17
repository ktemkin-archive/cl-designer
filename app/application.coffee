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
{VHDLExporter}  = require 'lib/exporters/vhdl_exporter'

class exports.QuickLogicApplication

  default_name: 'combinational'

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

    # Listen for changes to the design name.
    document.getElementById('designName').addEventListener('change', @handle_change)

    # Innitially, don't process any UI event.
    @active_ui_event = null

    # Start off assuming we've never seen valid side panel content.
    @last_valid_side_panel = ''

    # If we haven't seen this user before, show the help panel.
    @show_help() unless @datastore.get('seen')


  #
  # Sets up the handlers for all of the toolbar buttons.
  #
  set_up_toolbar: ->

    button_handlers =
      'btnNew':         @handle_new_click
      'btnOpen':        @handle_open_click
      'btnVHDLHTML5':   @handle_vhdl_export_html5_click
      'btnHelp':        @handle_help_click
      'btnDismissHelp': @handle_dismiss_help_click

    # Add each of the button handlers to their respective buttons.
    for id, handler of button_handlers
      document.getElementById(id).addEventListener('click', handler)
  
    # Create the flash-based download button, if Flash is supported.
    @set_up_download_button()
    @set_up_vhdl_export_button()


  #
  # Set up a better download experience, on systems that support Flash.
  # (The HTML5 download API doesn't allow a save dialog.)
  # 
  set_up_download_button: ->
    @_replace_button_with_downloadify('btnSaveHTML5', 'btnSave', => @serialize())


  #
  # Set up a better VHDL export experience, on systems that support Flash.
  # (The HTML5 download API doesn't allow a save dialog.)
  # 
  set_up_vhdl_export_button: ->
    
    #Replace the core VHDL export button... 
    @_replace_button_with_downloadify('btnVHDLHTML5', 'btnVHDL', (=> @to_VHDL(@get_design_filename())), 'vhd')

    #Add events on mouse-in and mouse-out, which will show and hide the error bar.
    export_area = document.getElementById('btnVHDL')
    export_area.addEventListener('mouseover', => @show_error_bar(@error_message())) 
    export_area.addEventListener('mouseout', => @show_error_bar(false))


  #
  # Replaces a given HTML5 download button with a Downloadify instance.
  # This allows for more dynamic saving using Flash's save dialog.
  #
  _replace_button_with_downloadify: (element_to_replace, target_element, generator_function, extension='eqs')->

    #Get a reference to the HTML5 save button we want to replace.
    download_button = document.getElementById(element_to_replace)

    # If supported, create a better download button using Downloadify.
    downloadify_options = 
      swf: 'flash/downloadify.swf'
      downloadImage: 'images/download.gif'
      width: download_button.offsetWidth
      height: download_button.offsetHeight
      append: true
      transparent: true
      filename: => "#{@get_design_filename()}.#{extension}"
      data: => generator_function()
    Downloadify.create(target_element, downloadify_options)


  #
  # Shows (or hides) the error bar.
  #
  # message: If a valid string message is provided, it will be displayed on the error bar;
  #          if the message is falsey, the error bar will be hidden.
  #
  show_error_bar: (message) ->

    #If we have a message to apply, apply it.
    if message
      document.getElementById('error_message').innerHTML = message 

    #Show or hide the error bar, as appropriate.
    error_bar = document.getElementById('error_bar')
    @set_element_opacity(error_bar, if message then 1 else 0)



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

    # Create the base editor, which is the primary user interface.
    @editor = ace.edit(@editor_div)
    @set_up_editor()

    # Attempt to restore the last design, if it exists.
    last_design = @datastore.get('autosave')
    @replace_with_serialized(last_design) if last_design


  #
  # Sets up the main editor, attaching the events necessary
  # for the application to run.
  #
  set_up_editor: =>

    #Update the editor's display each time the editor is changed.
    @editor.on('changeSelection', @handle_selection_change)
    @editor.on('change', @handle_change)


  #
  # Saves the currently running editor.
  #
  autosave: =>
    @datastore.set('autosave', @serialize())


  #
  # Handles modification of the editor.
  #
  handle_selection_change: =>
  
    #Fetch the expression that's just been modified.
    position_data = @editor.getSelectionRange().start
    expression    = @expression_at_position(position_data.row, position_data.column)

    #And use it to update the side display.
    @update_side_display(expression)


  #
  # Handles a change to the editor.
  #
  handle_change: =>
    @autosave()

    # Ensure that the export button is only available for valid designs.
    document.getElementById('btnVHDLHTML5').disabled = not @is_valid()
    @_add_or_remove_class(document.getElementById('btnVHDLHTML5'), 'nonempty', not @empty())
  
  
  #
  # Serializes the editor's state into a JSON string.
  #
  serialize: =>

    #TODO: Also include cursor position
    serialized =
      name: @get_design_name()
      equations: @editor.getValue()

    JSON.stringify(serialized)


  replace_with_serialized: (serialized) =>
    data = JSON.parse(serialized)
    console.log data

    @set_design_name(data.name)
    @editor.setValue(data.equations)
    
  #
  # Returns the current editor's document.
  #
  editor_document: =>
    @editor.getSession().getDocument()


  #
  # Returns the expression at the given position.
  #
  expression_at_position: (row_or_index, column = null ) =>

    #Extract an index from the passed argument, if necessary.
    if column
      position = {row: row_or_index, column: column}
      index = @editor_document().positionToIndex(position)
    else
      index = row_or_index

    #Get the raw value of the editor.
    raw_value = @editor.getValue()
  
    #If the character itself is a semicolon, parse the character before it.
    #This heuristic allows us to consider semicolons as "line terminators" rather
    #than separators.
    index = Math.max(index - 1, 0) if raw_value.charAt(index) == ";"
      
    #Find the end of the previous expression...
    end_of_previous_expression = raw_value.lastIndexOf(';', index)

    #... and the start of the next one.
    start_of_next_expression = raw_value.indexOf(';', index) 
    start_of_next_expression = raw_value.length if start_of_next_expression < 0

    #Extract the expression, and return it.
    raw_value.substring(end_of_previous_expression + 1, start_of_next_expression)



  #
  # Handles updating of the side panel.
  #
  update_side_display: (raw_expression) =>

    try
      
      #Render the side panel content.
      expression = new LogicEquation(raw_expression)
      content  = @render_interpretation(expression)
      content += @render_truth_table(expression.truth_table())
      @set_side_panel_content(content)

      #Store this as the last valid side panel.
      @last_valid_side_panel = content

    catch error

      #Don't render errors for empty expressions.
      return if raw_expression.trim() == ""

      #Otherwise, render the error message in the side bar.
      error_message = @render_error_message(error)
      @set_side_panel_content(error_message)


  #
  # Renders an error message in the sidebar.
  #
  render_error_message: (exception) =>
    "<div class=\"malformed\"><strong>Your input seems to be malformed:</strong></br></br>#{exception}</div>"


   #
   # Renders some vital information about how the information will be interpreted.
   #
  render_interpretation: (expression) ->
    interpretation  = "<div class=\"logic_interpretation\">"
    interpretation += "<strong>Output:</strong> #{expression.output}<br />"
    interpretation += "<strong>Inputs:</strong> #{expression.inputs.join(', ')}<br />"
    interpretation += "<strong>Interpreting as:</strong> <pre>#{expression.to_VHDL_expression()}</pre><br />"
    interpretation += "</div>"
    interpretation


  #
  # Renders a truth table in the right-most pane.
  #
  render_truth_table: (truth_table) =>
   
    #Start an array of HTML fragments.
    #(JavaScript strings are immutable, so string concatination
    # is a heavy operation. We'll use an array, and join the 
    # segments later.)
    # TODO: This apparently isn't true anymore; so perhaps remove this?
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

    #Return the rendered truth table.
    html.join('')


  #
  # Sets the HTML content of the side panel;
  # automatically adjusting its size, if necessary.
  #
  set_side_panel_content: (content) =>

    #Adjust the raw content of the side-panel bar.
    @sidebar.innerHTML = content


  #
  # Handles a click on the new button.
  #
  handle_new_click: =>
    @editor.setValue('')
    @set_design_name(@default_name)


  #
  # Handles the "Save" button; saves an equation file using a Data URI.
  # This method is not preferred, but will be used if Flash cannot be found.
  #
  handle_save_html5_click: =>
    
    #get a serialization of the FSM's state, for saving
    content = @serialize()
    
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

    # Clear the internal file selector.
    @_clear_file_selection()


  #
  # Loads a set of equations from an equation file.
  #
  load_from_file: (file) =>

    #create a new FileReader, and instruct it to
    # 1) read the file's contents, and
    # 2) pass the result to the text editor
    reader = new FileReader()
    reader.onload = (file) => @replace_with_serialized(file.target.result)
    reader.readAsText(file)


  #
  #
  # Returns an array of LogicEquation objects that describe the current editor input.
  #
  all_equations: ->
    try
      raw_equations = @editor.getValue().split(';')
      new LogicEquation(equation) for equation in raw_equations when equation.trim() != ""
    catch
      false



  #
  # Returns a list of all known outputs for the circuit being designed.
  #
  outputs: ->

    #Fetch an array of all output names for each of the given states...
    outputs = (equation.output for equation in @all_equations())

    #And flatten the array.
    @constructor.flatten_and_remove_duplicates(outputs)


  #
  # Returns a list of all known outputs for the circuit being designed.
  #
  inputs: ->

    #Fetch an array of all output names for each of the given states...
    inputs = (equation.inputs for equation in @all_equations())

    #And flatten the array.
    @constructor.flatten_and_remove_duplicates(inputs)



  #
  # Returns a string iff any of the I/O names are used for both an input
  # and an output. (This form of FSM can't be exported, at the moment.)
  #
  # If there is overlap, the first overlapping element will be returned.
  # If no overlap occurs, returns false.
  #
  inputs_and_outputs_overlap: ->
    inputs  = @inputs()
    outputs = @outputs()

    for input in inputs
      return input if input in outputs

    return false


  #
  # Flattens the given array and removes duplicate elements.
  #
  @flatten_and_remove_duplicates: (array) ->
   
    #Flatten the given array...
    array = [].concat(array...)

    #And find only the unique elements. 
    result = []
    for element in array
      element = element.toLowerCase()
      result.push(element) if element not in result


    result


  #
  # Returns the active design's name.
  #
  get_design_name: ->
    document.getElementById('designName').value


  #
  # Sets the active design's name, both in terms of the UI and the FSMDesigner.
  #
  set_design_name: (name) =>
    document.getElementById('designName').value = name


  #
  # Returns an appropriate filename for the active design.
  # TODO: Handle completely invalid names.
  #
  get_design_filename: =>
    @get_design_name().replace(/\s/g, '_').replace(/[^A-Za-z0-9_]/g, '')


  #
  # Returns true iff the given editor is empty.
  #
  empty: =>
    @editor.getValue().trim() == ""

  #
  # Returns a value iff the given Finite State Machine is valid, to the best of
  # the designer's knowledge. This indicates whether it can succesfully be
  # exported (but not whether the deisgn can be saved.)
  #
  is_valid: =>
    try
      inputs  = @inputs()
      outputs = @outputs()

      return false unless inputs.length > 0
      return false unless outputs.length > 0
      return false if @inputs_and_outputs_overlap()

      return true
    catch syntax_error
      return false
      

  #
  # Returns an HTML string containing the most relevant error message;
  # or false if the Finite State Machine is valid.
  #
  error_message: =>
    if @is_valid()
      return false
    else

      return " You haven't designed any <strong>logic</strong> yet!" if @empty()

      #Try to determine if the Finite State Machine has no arcs. 
      try
        return " At least one of your <strong>equations</strong> appears to have been entered incorrectly." if @outputs().length == 0

      #If we run into an error enumerating outputs, we must have had an invalid output somewhere.
      #Notify the user.
      catch syntax_error
        return " You'll need to fix the invalid <strong>equations</strong> below before you can create logic."

      overlap = @inputs_and_outputs_overlap()
      return " The name <strong>#{overlap}</strong> can't be used for both an <u>input</u> and an <u>output</u>." if overlap

      #If we don't have an invalid output, and the FSM _is_ invalid, then we must have an invalid arc.
      return " You'll need to fix the invalid <strong>equations</strong> below before you can create logic."


  #
  # Converts the current Finite State Machine to a VHDL design, if possible.
  #
  to_VHDL: (name = 'logic') ->
    return false unless @is_valid()
    generator = new VHDLExporter(@, name)
    generator.render()


  #
  # Handles the "export-to-VHDL" button; exports a VHDL file using a Data URI.
  # This method is not preferred, but will be used if Flash cannot be found.
  #
  handle_vhdl_export_html5_click: =>
    @_download_using_data_uri(@to_VHDL(@get_design_filename()))


  #
  # Forces download of the given file's content using a Data URI.
  #
  _download_using_data_uri: (content, mime_type='data:application/x-logic') ->

    #convert it to a data URI
    uri_content = "#{mime_type}," + encodeURIComponent(content)
    
    #and ask the user's browser to download it
    document.location.href = uri_content


  #
  # Adds or removes the given class depending on whether the provided condition is true.
  #
  _add_or_remove_class: (element, class_name, condition) ->
    if condition
      
      #Add the class, if it's not there already.
      unless element.className.indexOf(class_name) > -1
        element.className += " #{class_name} "

    else
      element.className = element.className.replace(" #{class_name} ", " ")


  #
  # Attempts to clear the hidden file selection.
  #
  _clear_file_selection: ->
    document.getElementById('fileOpen').value = ''



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
  # Show the help panel.
  #
  show_help: ->

    # Show the help panel...
    helpPanel = document.getElementById('helpPanel')
    @set_element_opacity(helpPanel, 1)

    # ... and mark it as seen.
    @datastore.set('seen', true)

