try:
    from Tkinter import *
    import tkMessageBox
except ImportError:
    from tkinter import *
    from tkinter import messagebox as tkMessageBox

from random import randint

import re
import serial
import struct
import serial.tools.list_ports
import sys
import time
try:
    from ctypes import windll
except ImportError:
    pass

# Configurable parameters related to UI appearance
canvas_width = 300
canvas_height = 400
inter_led_spacing_x = 80
led_diameter = 30

# Don't change this line; this script uses it to store serial port info
SERIAL_PORT = None
SERIAL_ATTRIBUTES_MATCH = ['device', 'hwid', 'vid', 'pid', 'serial_number']

# Non-UI Globals
ser = None          # The serial port object used to communicate with the board
timeout = 30        # How long should we try to look for the board?
ports_before = None # Serial ports on the system before plugging in
port_name = None    # Name of the serial port

def initialize_ui():
    global connect, connect_text, canvas, port, root

    # Setup the UI widgets (the canvas for the LEDs, and the connect box and button)
    root = Tk()

    canvas = Canvas(root, width=canvas_width, height=canvas_height)
    canvas.pack()
    canvas.bind("<Button-1>", canvas_click)

    label_port = Label(root, text="Port:")
    label_port.pack(side='left')

    port = StringVar(value='')

    entry_port = Entry(root, textvariable=port)
    entry_port.pack(side='left')

    connect_text = StringVar()
    connect = Button(root, textvariable=connect_text, command=connect_button)
    connect.pack(side='right')
    connect_text.set("Connect")

    # Draw the LEDs
    led_lines = [1,1,2,3,4,1]
    led_radius = led_diameter / 2
    led_idx = 0
    for i, leds_in_line in enumerate(led_lines):
        inter_led_spacing_y = canvas_height / (len(led_lines) + 1)
        led_offset_top = inter_led_spacing_y * (i + 1)
        #                ( center canvas  ) - (  span of the leds draw on this line  ) / 2
        led_start_left = (canvas_width / 2) - (inter_led_spacing_x * (leds_in_line-1)) / 2
        for j in range(leds_in_line):
            led_offset_left = led_start_left + inter_led_spacing_x * j
            canvas.create_oval(led_offset_left - led_radius, \
                               led_offset_top - led_radius, \
                               led_offset_left + led_radius, \
                               led_offset_top + led_radius, \
                               fill="white", \
                               tags='LEDNUM_%d' % (led_idx ))
            led_idx += 1

# UI callbacks
def connect_button():
    global ser

    if connect.cget('text') == "Disconnect":
        ser.close()
        port_name = None
        connect_text.set("Connect")
        return

    portname = port.get()
    if portname == '':
        tkMessageBox.showinfo('Setup xmas card connection',
            "We need to setup the connection to the card. " \
            "You'll only need to do this once. " \
            "First, unplug it if it's plugged in, then click OK.")
        port.set("OK; now plug it in")
        connect_text.set("Connecting")
        connect.config(state='disabled')
        timeout = 30
        root.after(1000, find_serial_port)
        return

    tkMessageBox.showerror("Unexpected problem", "Please restart.")

def canvas_click(event):
    if not ser:
        tkMessageBox.showerror("Error changing LED", \
                               "Click Connect button below.")
        return

    if canvas.find_withtag(CURRENT):
        if canvas.itemcget(CURRENT, "fill") == "white":
            newcolor = 'red'
            canvas.itemconfig(CURRENT, fill=newcolor)
        elif canvas.itemcget(CURRENT, "fill") == "red":
            newcolor = 'green'
            canvas.itemconfig(CURRENT, fill=newcolor)
        else:
            newcolor = 'white'
            canvas.itemconfig(CURRENT, fill=newcolor)

        lednum = int(canvas.gettags(CURRENT)[0].split('LEDNUM_')[1])

        canvas.update_idletasks()

        for idx, color in enumerate(('red', 'green')):
            update_led_intensity(lednum * 2 + idx, 7 if newcolor == color else 0)

# Serial port manipulation routines
def open_serial_port(device):
    """Try to open serial_port_name, raising an exception if it fails."""
    global ser

    try:
        postfixed_device = device
        if device.startswith('COM'):
            postfixed_device = device + ':'
        ser = serial.Serial(postfixed_device, 115200, timeout=1)
        set_led_display_mode(3)
        for i in range(24):
            update_led_intensity(i, 0)

    except Exception as e:
        error_message = str(e)
        print(repr(error_message))
        if error_message == '':
            error_message = 'Unknown error; are the wires loose?'
        tkMessageBox.showerror("Error opening serial port", error_message)
        return False
    return True

def is_same_serial_port():
    """Validates that the device described by serial_port_info is the same as
    what is presently connected to the machine under that device name."""
    ports = serial.tools.list_ports.comports() # Get all the ports in system
    for port in ports:
        if port.device == SERIAL_PORT['device']: # Find the one matching saved
            # Validate all the attributes we care about match
            all_match = True
            for attr in SERIAL_ATTRIBUTES_MATCH:
                if str(getattr(port, attr)) != SERIAL_PORT[attr]:
                    print("%s doesn't match. saved: %s now: %s" % (attr, SERIAL_PORT[attr], getattr(port, attr)))
                    all_match = False
                    break
            return all_match
    return False # Device not found

def open_serial_if_exists():
    """Tries to open saved SERIAL_PORT if exists and returns its name, otherwise
    returns an empty string."""

    # First attempt to open the saved serial port
    if SERIAL_PORT:
        if is_same_serial_port():
            open_serial_port(SERIAL_PORT['device'])
            port.set(SERIAL_PORT['device'])
            connect_text.set("Disconnect")
    
def find_serial_port():
    """Finds and attempts to save port to this script for future use."""
    global port_name, ports_before, timeout
    print('find_serial_port')

    if port_name:
        port.set(port_name)
        connect_text.set("Disconnect")
        connect.config(state='normal')
        return

    if ports_before == None:
        ports_before = serial.tools.list_ports.comports()

    ports_after = serial.tools.list_ports.comports()
    if len(ports_before) == len(ports_after) and timeout > 0:
        print('mismatch, rescheduling')
        timeout -= 1
        root.after(1000, find_serial_port)
        return

    if len(ports_before) + 1 != len(ports_after):
        tkMessageBox.showerror("Not found", \
            "Sadly, could not find it. You might need to install drivers.")
        connect_text.set("Connect")
        connect.config(state='normal')
        port.set("")
        ports_before = None
        return

    # Find which one was added
    for after in ports_after:
        found = False
        for before in ports_before:
            if before.device == after.device:
                found = True
                break
        if not found:
            new_port = after
            break

    port.set('Found it!')

    # Save it
    save_serial_port_info_to_script(new_port)
    if open_serial_port(new_port.device):
        port.set(new_port.device)
        port_name = new_port.device
        root.after(1000, find_serial_port)
    else:
        connect_text.set("Connect")
        connect.config(state='normal')
        port.set("")
        ports_before = None
        

def save_serial_port_info_to_script(serial_port_info):
    """Saves the serial port info to this script file's SERIAL_PORT variable for
    future use."""

    # Serialize the info
    info = serial_port_info
    infostr = '{'
    for attrname in SERIAL_ATTRIBUTES_MATCH:
        infostr += "'%s' : '%s', " % (attrname, getattr(info, attrname))
    infostr = infostr[:-2] + '}'

    print(infostr)
    # Open and read this script
    with open(sys.argv[0], 'r') as script_file:
        script_contents = script_file.read()

    # Replace the config variable
    updated_script = re.sub('\nSERIAL_PORT = (.*)\n',
                            '\nSERIAL_PORT = %s\n' % (infostr),
                            script_contents)

    # Write it back out (to a different filename for now for debugging.)
    with open('new.py', 'w') as new_script_file:
        new_script_file.write(updated_script)

def dump_port_info(port):
    print('device:      %s' % (port.device))
    print('description: %s' % (port.description))

# LED manipulation routines
def set_led_display_mode(mode):
    # Switch mode to individual LED control
    ser.write('m'.encode())
    ser.write(b'\x03') # 0: free running, 1: stored pattern, 2: random, 3: individual LEDs
    readback = ser.read()
    assert len(readback) == 1
    assert readback == b'\x03'

def update_led_intensity(led, intensity):
    '''Updates a given led (0-23)'s intensity (0-7, 0: off, 7: full on)
    on the xmas tree board by sending commands to already open 'ser' object.'''
    try:
        ledb = struct.pack('B', led)
        assert len(ledb) == 1

        intensityb = struct.pack('B', intensity)
        assert len(intensityb) == 1

        ser.write('i'.encode())
        ser.write(ledb)
        ser.write(intensityb)

        readback = ser.read()
        assert len(readback) == 1
        assert readback == ledb

        readback = ser.read()
        assert len(readback) == 1
        assert readback == intensityb
    except Exception as e:
        tkMessageBox.showerror("Error changing LED", str(e))

def map_led_bulb_and_color_to_led_pin(led_bulb, color):
    '''Maps a given LED bulb (0-11) and color 'red, blue' to a physical pin on
    the FPGA (0-23) controlling that color in that LED bulb.'''
    pass

try:
    windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    pass
p = open_serial_if_exists()
initialize_ui()
root.mainloop()