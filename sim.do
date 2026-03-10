# Create the work library
vlib work
vmap work work

# Compile the source files
# Note: Ensure 'fifo.sv' is in the same directory as it is instantiated in fft_top.sv [cite: 110, 112]
vlog -sv fft.sv
vlog -sv fft_top.sv
vlog -sv fft_tb.sv

# Load the simulation
# We use the testbench module name 'fft_tb' [cite: 119]
vsim -voptargs="+acc" work.fft_tb

#==========================================================================
# Waveform Setup
#==========================================================================
add wave -divider "Global Signals"
add wave -noupdate -color "Yellow" /fft_tb/clk
add wave -noupdate -color "Yellow" /fft_tb/rst_n

add wave -divider "Input Interface"
add wave -noupdate -format Analog-Step -height 40 -max 32767 -min -32768 /fft_tb/in_re_din
add wave -noupdate /fft_tb/in_re_wr_en
add wave -noupdate /fft_tb/in_re_full
add wave -noupdate /fft_tb/in_im_wr_en

add wave -divider "Internal FSM & Memory"
add wave -noupdate /fft_tb/dut/fft_inst/state_r
add wave -noupdate /fft_tb/dut/fft_inst/stage_idx_r
add wave -noupdate /fft_tb/dut/fft_inst/bfly_idx_r

add wave -divider "Output Interface"
add wave -noupdate /fft_tb/out_re_empty
add wave -noupdate /fft_tb/out_re_rd_en
add wave -noupdate -format Analog-Step -height 40 -max 32767 -min -32768 /fft_tb/out_re_dout
add wave -noupdate -format Analog-Step -height 40 -max 32767 -min -32768 /fft_tb/out_im_dout

# Run the simulation
run -all