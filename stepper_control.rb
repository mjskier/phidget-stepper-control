#!/usr/bin/env ruby

require 'tk'
require 'phidgets-ffi'
require 'ap'

require './joystick'

# ------------ Class Defs ----------

class PhidgetStepper1062

  attr_accessor :vars, :labels, :entries

  include KeywordProcessor

  def initialize(args = {}.freeze)
    # What kind of args do we want to handle
    # - Number of motos and indexs might be a good idea.
    # - which one is in what direction...

    # - MotorPositionMin
    # - MotorPositionMax
    # - CurrentMotorPosition (Initial position is middle of the above 2)
    # - velocitylimit (bounded by velocitymax and velocitymin)
    # - engaged false?
    
    # These 2 are arbitrary to test stuff

    @max_x = 2000
    @max_y = 2000

    create_gui
    init_phidget
  end

  def log_info(msg)
    # puts "-I- #{msg}"
    @msg_text.insert('end', "-I- #{msg}\n")
  end

  def log_error(msg)
    # puts "-E- #{msg}"
    @msg_text.insert('end', "-E- #{msg}\n")
  end

  # ---------------- The GUI callbacks ---------------------

  def engaged_changed
    num = @vars['motor_number'].value.to_i
    return if @device.nil?

    if @vars['engaged'].value.to_i.eql? 1
      log_info("Turning motor #{num} on")
      @device.steppers[num].engaged = true
    else
      log_info("Turning motor #{num} off")
      @device.steppers[num].engaged = false
    end
  end

  def max_velocity_slider(var)
    val = var.value.to_f
    num = @vars['motor_number'].value.to_i
    # puts "max_velocity slider value for motor #{num}: #{val}"
    @device.steppers[num].velocity_limit = val
  end

  def acceleration_slider(var)
    val = var.value.to_f
    num = @vars['motor_number'].value.to_i
    # puts "acceleration_slider value for motor #{num}: #{val}"
    @device.steppers[num].acceleration = val
  end

  def target_position_slider(var)
    val = var.value.to_i
    num = @vars['motor_number'].value.to_i
    begin
      @device.steppers[num].target_position = val
    rescue Exception => e
      puts "Exception caught: #{e.message}"
    end
  end

  def actual_position_slider(var)
    val = var.value.to_i
    num = @vars['motor_number'].value.to_i
    until @device.steppers[num].stopped
      puts "Waiting for motor #{num} to stop"
      sleep 1
    end
    @device.steppers[num].current_position = val
  end

  def motor_selected
    num = @vars['motor_number'].value.to_i
    log_info("New motor selected:  #{num}")

    # Change the scale of the sliders to match the range of 
    # the controller/motors

    @vls.from(@velocity_mins[num])
    @vls.to(@velocity_maxs[num])
    @sas.from(@acc_mins[num])
    @sas.to(@acc_maxs[num])

    # Change the value of the motor data fields

    @vars['max_velocity'].value = @device.steppers[num].velocity_max
    @vars['actual_velocity'].value = @device.steppers[num].velocity
    @vars['acceleration'].value = @device.steppers[num].acceleration
    @vars['target_position'].value = @device.steppers[num].target_position
    @vars['actual_position'].value = @device.steppers[num].current_position
  end

  # ---------------- The Phidget related stuff ---------------------

  def init_phidget
    Phidgets::Log.enable(:verbose, nil)
    @sc = Phidgets::Stepper.new
    log_info("Waiting for PhidgetStepper to attach...")

    # Get some info from the phidget
    # register callbacks

    @sc.on_attach do |device, obj|
      log_info("Device attributes: #{device.attributes} attached")
      @device = device

      @vars['Attached'].value = 'true'
      @vars['# Steppers'].value = @device.steppers.size
      @vars['Name'].value = @device.name
      @vars['Serial No'].value = @device.serial_number
      @vars['Version'].value = @device.version

      @acc_steps = Array.new
      @acc_mins = Array.new
      @acc_maxs = Array.new
      @velocity_mins = Array.new
      @velocity_maxs = Array.new

      for i in 0..(@device.steppers.size - 1 )
	@acc_mins[i] = @device.steppers[i].acceleration_min
	@acc_maxs[i] = @device.steppers[i].acceleration_max

	@velocity_mins[i] = @device.steppers[i].velocity_min
	@velocity_maxs[i] = @device.steppers[i].velocity_max

	# Manual says sets a default value for acceleration. 
        # Otherwise it could be anything
	@device.steppers[i].acceleration =  @acc_maxs[i]
	# 1 acceleration step since our joystick goes from 0 to 100
	@acc_steps[i] = (@acc_maxs[i] - @acc_mins[i]) / 100
	@device.steppers[i].current_position =  0
      end

      @device.steppers[0].velocity_limit = @device.steppers[0].velocity_max
      @device.steppers[0].acceleration = @acc_maxs[0]

      # Need to update the slider scales now that we can query limits
      motor_selected
    end

    @sc.on_detach do |device, obj|
      log_info("#{device.attributes.inspect} detached")
      @device = nil
    end

    @sc.on_error do |device, obj|
      log_error("Error #{code}: #{description}")
    end

    @sc.on_position_change do |device, stepper, position, obj|
      @vars['actual_position'].value = position
    end
  end

  # We get a joystick x and y position (in term of +-percent from maximum position)
  # We also get a rate of change from the previous position.
  #
  # px, px are percentage to edge of joystick movement.
  #  ex for y: 100 is pushed all the way, -100 is pulled all the way
  #
  # dx, dy are changes compared to the previous position.
  #

  # Motor 0 is x direction.
  # Motor 1 is y direction.

  def joystick_event(e, px, py, dx, dy)
    if @device.nil?
      log_info("Device not attached yet")
      return
    end

    case e
    when Joystick::POSITION

      log_info("New position: #{px}, #{py}")

      @device.steppers[0].acceleration = @acc_maxs[0]

      # Set motor(s) target
      if (px > 0)
	@device.steppers[0].target_position = @max_x
	@vars['target_position'].value = @device.steppers[0].target_position
	@device.steppers[0].engaged = true
      elsif (px < 0)
	@device.steppers[0].target_position = -@max_x
	@vars['target_position'].value = @device.steppers[0].target_position
	@device.steppers[0].engaged = true
      else
	@device.steppers[0].engaged = false
      end

    when Joystick::DELTA

      # Raise/lower motor(s) acceleration
      # Need to know if we have reversed the direction...
      puts "@device.steppers[0].acceleration: #{@device.steppers[0].acceleration}"
      puts "dx: #{dx}"
      puts "@acc_steps[0]: #{@acc_steps[0] }"

      new_dx = @device.steppers[0].acceleration + dx * @acc_steps[0] 
      if(new_dx < 0)
	new_dx = new_dx.abs
	@device.steppers[0].target_position = - @device.steppers[0].target_position
      end

      @device.steppers[0].acceleration = @acc_maxs[0]

    when Joystick::RELEASE

      log_info("Release: #{px}, #{py}")

      # Stop the motor
      @device.steppers[0].engaged = false
      @device.steppers[1].engaged = false

      # set acceleration to min 
      @device.steppers[0].acceleration =  (@device.steppers[0].acceleration_min) * 2
      @device.steppers[1].acceleration =  (@device.steppers[1].acceleration_min) * 2
    else
      log_error("Unknown joystick event at: #{px}, #{py}")
      # Stop the motor?
      @device.steppers[0].engaged = false
      @device.steppers[1].engaged = false
    end

  end

  # ---------------- The GUI creation ---------------------

  def create_gui

    # hold the control variable, label widget, and text entry widget
    # for each entries in the detail panel

    @vars = Hash.new
    @labels = Hash.new
    @entries = Hash.new

    # The root

    root = TkRoot.new { title "Stepper Control" }
    TkGrid.columnconfigure root, 0, :weight => 1
    TkGrid.rowconfigure root, 0, :weight => 1

    # Enclosing frame

    content = Tk::Tile::Frame.new(root) { padding "5 5 12 12" }
    content.grid :sticky => 'nsew'

    # -------------- Controller Details frame --------------

    details = Tk::Tile::Labelframe.new(content) { text 'Stepper Control Details' }
    details.grid :column => 0, :row => 0, :sticky => 'nsew', :columnspan => 4
    details['borderwidth'] = 2

    # Entries in the details frame

    row = 0

    [ 'Attached', 'Name', 'Serial No', 'Version', '# Steppers' ].each do |label|
      @vars[label] = TkVariable.new
      @vars[label].value = 'unknown'
      @labels[label] = Tk::Tile::Label.new(details) { text "#{label}:" }
      @labels[label].grid :column => 0, :row => row, :sticky => 'ew'
      @entries[label] = Tk::Tile::Entry.new(details, :textvariable => @vars[label] )
      @entries[label].grid :column => 1, :row => row, :sticky => 'ew'
      row += 1
    end

    TkWinfo.children(details).each {|w| TkGrid.configure w, :padx => 5, :pady => 3}
    TkGrid.columnconfigure(content, 0,	:weight => 1)

    # -------------- Motor Data --------------

    # These are the text or control variables attached to widgets

    @vars['motor_number'] = TkVariable.new { value 0 }
    @vars['max_velocity'] = TkVariable.new { value 0 }
    @vars['max_velocity2'] = TkVariable.new { value 0 }
    @vars['actual_velocity'] = TkVariable.new { value 0 }
    @vars['acceleration'] = TkVariable.new { value 0 }
    @vars['target_position'] = TkVariable.new { value 0 }
    @vars['actual_position'] = TkVariable.new { value 0 }
    @vars['engaged'] = TkVariable.new { value 0 }
    @vars['stopped'] = TkVariable.new { value 0 }

    # The enclosing Motor Data frame

    data = Tk::Tile::Labelframe.new(content) { text 'Motor Data' }
    data.grid :column => 0, :row => 1, :sticky => 'nsew', :columnspan => 4
    data['borderwidth'] = 2

    # Motor selection

    cl = Tk::Tile::Label.new(data) { text 'Stepper Motor:' }
    cl.grid :column => 0, :row => 0, :sticky => 'nw'

    cs = Tk::Tile::Combobox.new(data, :textvariable => @vars['motor_number'])
    cs.values = [ '0', '1', '2', '3' ]
    cs.bind("<ComboboxSelected>") { motor_selected }
    cs.grid :column => 1, :row => 0, :sticky => 'nw'
    @vars['motor_number'].value = 0

    # The value displays

    mvl = Tk::Tile::Label.new(data) { text 'Max Velocity:' }
    mvl.grid :column => 0, :row => 1, :sticky => 'e'
    mvt = Tk::Tile::Entry.new(data, :textvariable => @vars['max_velocity'] )
    mvt.grid :column => 1, :row => 1, :sticky => 'ew'
    @vars['max_velocity'].value = 0

    avl = Tk::Tile::Label.new(data) { text 'Actual:' }
    avl.grid :column => 2, :row => 1, :sticky => 'e'
    avt = Tk::Tile::Entry.new(data, :textvariable => @vars['actual_velocity'] )
    avt.grid :column => 3, :row => 1, :sticky => 'ew'
    @vars['actual_velocity'].value = 0

    al = Tk::Tile::Label.new(data, :text => 'Acceleration:' )
    al.grid :column => 0, :row => 2, :sticky => 'e'
    at = Tk::Tile::Entry.new(data, :textvariable => @vars['acceleration'] )
    at.grid :column => 1, :row => 2, :sticky => 'ew'
    @vars['acceleration'].value = 0

    ptl = Tk::Tile::Label.new(data) { text 'Position Target:' }
    ptl.grid :column => 0, :row => 3, :sticky => 'e'
    ptt = Tk::Tile::Entry.new(data, :textvariable => @vars['target_position'] )
    ptt.grid :column => 1, :row => 3, :sticky => 'ew'
    @vars['target_position'].value = 0

    apl = Tk::Tile::Label.new(data) { text 'Actual:' }
    apl.grid :column => 2, :row => 3, :sticky => 'e'
    apt = Tk::Tile::Entry.new(data, :textvariable => @vars['actual_position'] )
    apt.grid :column => 3, :row => 3, :sticky => 'ew'
    @vars['actual_position'].value = 0

    # add a separator

    s1 = Tk::Tile::Separator.new(data) {
      orient 'horizontal'
    }
    s1.grid :column => 0, :row => 4, :columnspan => 4, :sticky => 'ew'

    # The check buttons

    engaged_button = Tk::Tile::CheckButton.new(data, :text => 'Engaged', 
					       :variable => @vars['engaged'],
					       :command => proc { engaged_changed })
    engaged_button.grid :column => 0, :row => 5, :sticky => 'ew'

    stopped_button = Tk::Tile::CheckButton.new(data, :text => 'Stopped', :variable => @vars['stopped'])
    stopped_button.grid :column => 1, :row => 5, :sticky => 'ew'

    s2 = Tk::Tile::Separator.new(data, :orient => 'horizontal')
    s2.grid :column => 0, :row => 6, :columnspan => 4, :sticky => 'ew'

    # The sliding bars

    # Max Velocity

    vll = Tk::Tile::Label.new(data) { text 'Max Velocity:' }
    vll.grid :column => 0, :row => 7, :sticky => 'ew'
    @vls = Tk::Tile::Scale.new(data, :orient => 'horizontal',
			       :length => 100, :from => 1, :to => 100,
			       :variable => @vars['max_velocity'],
			       :command => proc { max_velocity_slider(@vars['max_velocity']) })
    @vls.grid :column => 0, :row => 8, :sticky => 'ew', :columnspan => 2

    # Acceleration

    sal = Tk::Tile::Label.new(data) { text 'Acceleration:' }
    sal.grid :column => 0, :row => 9, :sticky => 'ew'
    @sas = Tk::Tile::Scale.new(data, :orient => 'horizontal', :length => 100,
			       :from => 1, :to => 100,
			       :variable => @vars['acceleration'],
			       :command => proc { acceleration_slider(@vars['acceleration']) })
    @sas.grid :column => 0, :row => 10, :sticky => 'ew', :columnspan => 2

    # Target

    stl = Tk::Tile::Label.new(data) { text 'Target Position:' }
    stl.grid :column => 0, :row => 11, :sticky => 'ew'
    @sts = Tk::Tile::Scale.new(data, :orient => 'horizontal',
			       :length => 100, :from => -@max_x, :to => @max_x,
			       :variable => @vars['target_position'],
			       :command => proc { target_position_slider(@vars['target_position']) })
    @sts.grid :column => 0, :row => 12, :sticky => 'ew', :columnspan => 2

    # Current Position

    scl = Tk::Tile::Label.new(data) { text 'Current Position:' }
    scl.grid :column => 0, :row => 13, :sticky => 'ew'
    @scs = Tk::Tile::Scale.new(data, :orient => 'horizontal', :length => 100, :from => -@max_x, :to => @max_x,
			       :variable => @vars['actual_position'],
			       :command => proc { actual_position_slider(@vars['actual_position']) })
    @scs.grid :column => 0, :row => 14, :sticky => 'ew', :columnspan => 2

    # --------- The joystick Canvas ---------------

    @canvas = TkCanvas.new(data)
    @canvas.grid :column => 3, :row => 7, :sticky => 'w', :rowspan => 8

    # Create a joystick and register our callback. This is for our x-y motion
    @joystick = Joystick.new(@canvas, :x => 105, :y => 105)
    @joystick.subscribe do |e, px, py, dx, dy| joystick_event(e, px, py, dx, dy) end

    # The message logging frame

    mf = Tk::Tile::Labelframe.new(content) { text 'Messages' }
    mf.grid :column => 0, :row => 3, :sticky => 'nsew', :columnspan => 6
    mf['borderwidth'] = 2

    
    TkGrid.columnconfigure(mf, 0, :weight => 1)
    TkGrid.rowconfigure(mf, 0, :weight => 1)

    @msg_text = TkText.new(mf) { height 10; background "white" }
    @msg_text.grid :column => 0, :row => 2
    @msg_text['state'] = :normal

    TkWinfo.children(content).each {|w| TkGrid.configure w, :padx => 5, :pady => 5}
    TkWinfo.children(data).each {|w| TkGrid.configure w, :padx => 5, :pady => 3}

  end # create_gui

end # class PhidgetStepper1062

# ------------- Main -------------

controller = PhidgetStepper1062.new
Tk.mainloop

