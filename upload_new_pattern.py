import argparse
import sys
import serial
import struct

parser = argparse.ArgumentParser()
parser.add_argument("com_port", help="The com port of the FPGA (ex: 'COM3:')")
parser.add_argument("pattern_file", help="A text file containing the new pattern to program")
args = parser.parse_args()

# Read the contents of the pattern file.
pattern = []
with open(args.pattern_file, 'r') as f:
    for line in f:
        pattern.append(line.strip())

# Program it to the FPGA.
# Open the serial port; this will raise an exception if not found.
with serial.Serial(args.com_port, 115200, timeout=1) as ser:
    print('Serial port opened. Sending pattern. Should take about 5 seconds.')
    # Switch the board to pattern display mode.
    mode_byte = struct.pack('B', int(1))
    ser.write('m'.encode())
    ser.write(mode_byte) 
    readback = ser.read()
    assert len(readback) == 1
    assert readback == mode_byte

    # Upload the pattern.
    for idx, line in enumerate(pattern):
        ser.write('w'.encode()) # Start a new address upload with special 'w' delimiter
        address = struct.pack('B', idx) # RAM indexes from 0 - 255
        assert len(address) == 1
        ser.write(address)
        # Each line is 9 bytes in hex. From most to least significant, send each.
        for byte_idx in range(len(line) // 2):
            hex_byte = line[byte_idx*2 : (byte_idx+1)*2]
            int_byte = int(hex_byte, 16)
            byte = struct.pack('B', int_byte)
            assert len(byte) == 1
            ser.write(byte)
        # Expect an 'o' acknowledgement in response
        ack = ser.read()
        if ack != b'o':
            print('Error writing line', idx, repr(ack))
            break
        # Read 10 bytes back in confirmation
        addr_back = ser.read(1)
        assert len(addr_back) == 1
        assert address == addr_back

        data_back = ser.read(9)
        assert len(data_back) == 9
        for byte_idx in range(len(line) // 2):
            hex_byte = line[byte_idx*2 : (byte_idx+1)*2]
            int_byte = int(hex_byte, 16)
            byte = struct.pack('B', int_byte)
            byte_back = struct.pack('B', data_back[byte_idx])
            try:
                assert byte == byte_back
            except AssertionError:
                print('fv:', byte_idx, repr(byte), repr(byte_back))

        done_byte = ser.read(1)
        assert len(done_byte) == 1
        assert done_byte == b'd'
    print('Completed sending data.')