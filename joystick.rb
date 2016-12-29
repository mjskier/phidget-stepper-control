#!/usr/bin/env ruby

require 'tk'
require './kwprocessor'

# parent, assume a canvas
# joystick: Base image
# knob:     The part that will move
# x, y:     Position in the canvas

class Joystick

  attr_reader :range_x, :range_y 

  POSITION	= 1	# Knob goes from origin to a position
  DELTA		= 2	# Knob moves from a previous position
  RELEASE	= 3	# Knob is released

  include KeywordProcessor

  def initialize(parent, args = {}.freeze)
    args = process_params(args, { 
			    joystick:  'joystick.gif',
			    knob:      'knob.gif',
			    x:          0,
			    y:          0,
			    # callback?
			  })

    @canvas = parent
    @parent_cb = args[:oarent_cb]

    # The joystick and knob

    @joystick_img = TkPhotoImage.new(:file => args[:joystick])
    @knob_img = TkPhotoImage.new(:file => args[:knob])

    # Some info about the joystick that is used over and over

    @range_x = @joystick_img.width / 2
    @range_y = @joystick_img.height / 2
    @joystick_center_x = args[:x] || @range_x
    @joystick_center_y = args[:y] || @range_y
    @x_offset = @joystick_center_x - @range_x
    @y_offset = @joystick_center_y - @range_y

    @joystick = TkcImage.new(@canvas, @joystick_center_x, @joystick_center_y, :anchor => 'center', :image => @joystick_img)
    @knob = TkcImage.new(@canvas, @joystick_center_x, @joystick_center_y, :anchor => 'center', :image => @knob_img)
    @knob_x = @joystick_center_x
    @knob_y = @joystick_center_y

    # I have to do both since the images overlap, creating a dead zone if I only bind to one.
    # Maybe cleaner to create a canvas instead and do the event binding there?

    @joystick.bind( "1", proc { |x, y| button1_pressed(x, y) }, "%x %y")
    @joystick.bind( "B1-Motion", proc { |x, y| button1_dragged(x, y) }, "%x %y")
    @joystick.bind( "ButtonRelease-1", proc { |x, y| button1_released(x, y) }, "%x %y")
    @knob.bind( "1", proc { |x, y| button1_pressed(x, y) }, "%x %y")
    @knob.bind( "B1-Motion", proc { |x, y| button1_dragged(x, y) }, "%x %y")
    @knob.bind( "ButtonRelease-1", proc { |x, y| button1_released(x, y) }, "%x %y")
  end

  # Register a callback for the parent

  def subscribe(&callback)
    @parent_callback = callback
  end

  # Call the parent with movement information
  # px, py are percentages away from center.
  # 0,0 is at the knob rest postion (center of the image)
  #
  #                0,100
  #      -100,0    0,0    100,0
  #                0,-100
  #

  def notify(e, px, py, dx, dy)
    @parent_callback.call(e, px, py, dx, dy) if @parent_callback
  end
 
  # Prevent x and/or y from moving out of the joystick circle

  def constrain_xy(x, y)

    x = @x_offset if x < @x_offset
    x = @joystick_img.width + @x_offset if x > @joystick_img.width + @x_offset
    y = @y_offset if y < @y_offset
    y = @joystick_img.height + @y_offset if y > @joystick_img.height + @y_offset

    return x, y
  end

  # Event callbacks

  def button1_pressed(x, y)
    x, y = constrain_xy(x, y)
    dx = x - @knob_x
    dy = y - @knob_y
    @canvas.move(@knob, dx, dy)
    @knob_x = x
    @knob_y = y

    px, py = position_percent(x, y)
    notify(POSITION, px, py, dx, dy)
  end

  def button1_released(x, y)
    dx = @joystick_center_x - @knob_x
    dy = @joystick_center_y - @knob_y
    @canvas.move(@knob, dx, dy)

    @knob_x = @joystick_center_x
    @knob_y = @joystick_center_y
    notify(RELEASE, 0, 0, 0, 0)
  end

  def button1_dragged(x, y)
    x, y = constrain_xy(x, y)

    dx = x - @knob_x
    dy = y - @knob_y
    @canvas.move(@knob, dx, dy)
    @knob_x = x
    @knob_y = y

    px, py = position_percent(x, y)
    notify(DELTA, px, py, dx, dy)
  end

  def position_percent(x, y)
    px = ((x - @joystick_center_x).to_f / @range_x.to_f * 100.0).to_i
    py = ( (@joystick_center_y - y).to_f / @range_y.to_f * 100.0).to_i
    return px, py
  end

end
