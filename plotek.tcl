#!/bin/sh
# Start wish from command shell \
exec tclsh "$0" ${1+"$@"}

#
# ProcTek - process CSV files from a Tektronix Scope
#
# Copyright (C) 2020, Neil Johnson
#
# Tested with files from a Tek DPO2024B
#

package require Tk
package require csv
package require struct::matrix

# Plot data is stored in a matrix for easy CSV import and processing
::struct::matrix plotData

# All info about the plot is stored in a global array

proc initPlot {} {
	global plotData
	global plotInfo

	if {[plotData columns] > 0} {
		plotData destroy
		::struct::matrix plotData
		unset plotInfo
	}
	
	# -- Default to colour plots
	set plotInfo(monochrome) false

	# -- Define plot sizes, then set default to medium
	set plotInfo(size,large)  "1920,1280"
	set plotInfo(size,medium) "1200,800"
	set plotInfo(size,small)  "640,480"
	set plotInfo(size)        medium

	# -- Plots can have titles
	set plotInfo(title) ""
}


############################################################################
#
# Load the CSV data file into memory
#
proc readDataFile {fname} {
	global plotData
	
	initPlot
	puts "Reading $fname ..."
	set chan [open $fname]
	csv::read2matrix $chan plotData , auto
	close $chan

	enumerateTraces

	puts "Done."
}

# ############################################################################
#
# Scan a data file enumerating the scope traces
#
proc enumerateTraces {} {
	global plotData
	global plotInfo

	set trc 0
	set i 0
	
	puts "Scanning data..."
	for {set c 0} {$c < [plotData columns]} {incr c 6} {
		set name [plotData get cell [expr $c + 1] 6]
		puts "  found dataset $name"
		if {[string match "Glitch*" $name] == 0} {
			set plotInfo(trace,$i,idx) $c
			set plotInfo(trace,$i,name) $name
			set plotInfo(trace,$i,show) false
			puts "  adding plot $i"
			incr i
		}
	}
	set plotInfo(trace,count) $i
	puts "Done."
}

# ############################################################################
#
# Generate plot data based on the data in plotData and the settings in plotInfo
#
proc generatePlot {} {
	global plotData
	global plotInfo

	puts "Generating Scope Traces..."

	set ofile [open "tekplots.cmd" w]
	set rows [plotData rows]

	set plotCmd ""

	for {set i 0} {$i < $plotInfo(trace,count)} {incr i} {
		set enabled $plotInfo(trace,$i,show)
		set base    $plotInfo(trace,$i,idx)

		# Extract trace parameters
		set params          [plotData get rect [expr $base + 1] 0 [expr $base + 1] 15]
		set recLength 		[lindex $params 0]
		set sampleInterval 	[lindex $params 1]
		set triggerPoint	[lindex $params 2]
		set source			[lindex $params 6]
		set vertUnits		[lindex $params 7]
		set vertScale		[lindex $params 8]
		set vertOffset		[lindex $params 9]
		set horizUnits		[lindex $params 10]
		set horizScale		[lindex $params 11]
		set ptFmt			[lindex $params 12]
		set yZero			[lindex $params 13]
		set probeAtten		[lindex $params 14]
		set note			[lindex $params 15]

		if {$i == 0} {
			puts $ofile "set key off"
			puts $ofile "set lmargin 10"

			if {$plotInfo(title) != ""} {
				#puts "set title \"[data get cell [expr $base + 1] 6] ([data get cell [expr $base + 1] 16])\""
				puts $ofile "set title \"$plotInfo(title)\""
				puts $ofile "show title"
			}

			set div $horizScale
			set mult ""
			if {$div < 1.0} {
				set div [expr $div * 1000]
				set mult "m"
			}
			if {$div < 1.0} {
				set div [expr $div * 1000]
				set mult "u"
			}
			if {$div < 1.0} {
				set div [expr $div * 1000]
				set mult "n"
			}
			puts "H: $div"
			set div [expr int($div)]
			puts $ofile "set xlabel \"$div $mult$horizUnits/div\""
			puts $ofile "set xtics format \"\""

			# Note to self: need to accomodate probe attenuation

			set div $vertScale
			set mult ""
			if {$div < 1.0} {
				set div [expr $div * 1000]
				set mult "m"
			}
			if {$div < 1.0} {
				set div [expr $div * 1000]
				set mult "u"
			}
			if {$div < 1.0} {
				set div [expr $div * 1000]
				set mult "n"
			}
			puts "V: $div"
			set div [expr int($div)]
			puts $ofile "set ylabel \"$div $mult$vertUnits/div\""
			puts $ofile "set yrange \[ -[expr $vertScale * 4] : [expr $vertScale * 4]\]"
			puts $ofile "set ytics $vertScale format \"\""

			puts $ofile "set grid xtics ytics"

			set size $plotInfo(size,$plotInfo(size))
			puts "Plot size = $size"
			puts $ofile "set terminal gif size $size"
			puts $ofile "set output \"tekplots.gif\""
		}

		puts " Trace $i is $enabled"

		if {$enabled} {
			puts $ofile "\$ScopeTrace$i << EOD"
			for {set row 0} {$row < $rows} {incr row} {
				set point [plotData get rect [expr $base + 3] $row [expr $base + 4] $row]
				puts $ofile [format "%.6f %.6f %.6f" [lindex [lindex $point 0] 0] [expr [lindex [lindex $point 0] 1] + $vertScale * $yZero] $vertOffset]
			}
			puts $ofile "EOD"
			set colour ""
			if {$plotInfo(monochrome)} {
				set colour "lc \"black\""
			}
			set thisplot " \$ScopeTrace$i using 1:2 with lines $colour title \"$plotInfo(trace,$i,name)\" at beginning,"
			# \$ScopeTrace$i using 1:3 with lines title \"\" $colour, "
			append plotCmd $thisplot
		}
	}

	puts $ofile "plot $plotCmd"

	puts "Done."
   
   close $ofile
}

# ############################################################################
#
# Set up the GUI
#
proc buildGUI {} {
	global plotInfo

   . config -menu .menubar
   menu .menubar

   .menubar add cascade -label "File" -menu .menubar.file
      menu .menubar.file -tearoff no
      .menubar.file add command -label "Open" -command { m_openFile }
      .menubar.file add separator
      .menubar.file add command -label "Exit" -command { exit }

   .menubar add command -label "Traces" -command { m_Traces }

   .menubar add cascade -label "Options" -menu .menubar.options
      menu .menubar.options -tearoff no
      .menubar.options add checkbutton -label "Monochrome" -variable plotInfo(monochrome)
	  .menubar.options add cascade -label "Size" -menu .menubar.options.size
	  menu .menubar.options.size -tearoff no
	  .menubar.options.size add radiobutton -label "Small" -variable plotInfo(size)  -value "small"
	  .menubar.options.size add radiobutton -label "Medium" -variable plotInfo(size) -value "medium"
	  .menubar.options.size add radiobutton -label "Large" -variable plotInfo(size)  -value "large"
   
   .menubar add command -label "PLOT" -command { m_plotTraces }
   
   .menubar add cascade -label "Help" -menu .menubar.help
      menu .menubar.help -tearoff no
      .menubar.help add command -label "About" -command { m_About }

   canvas .c
   pack .c -expand true -fill both -side top -anchor n
}

# ############################################################################
#
# Menu action: show about dialog box
#
proc m_About {} {
	tk_messageBox -title "About" \
		-message "PloTek - Tektronix Plot Post Processor" \
		-detail "Copyright (c) 2020 Neil Johnson" \
		-type ok \
		-icon info
}

# ############################################################################
#
# Menu action: manage traces
#
proc m_Traces {} {
	global plotInfo
	set button 0

	toplevel .t 
	wm title .t "Plotek - Traces"
	
	frame .t.l -relief raised -borderwidth 2
	# Headings
	label .t.l.show -text "Show"
	label .t.l.label -text "Label"
	grid .t.l.show .t.l.label -sticky nsew
	grid columnconfigure .t.l 0 -weight 0
	grid columnconfigure .t.l 1 -weight 1
	frame .t.l.bar -height 1 -bg black
	grid .t.l.bar - -sticky news -pady 1

	# Traces
	for {set i 0} {$i < $plotInfo(trace,count)} {incr i} {
		puts " UI trace $i"
		checkbutton .t.l.cb$i -variable plotInfo(trace,$i,show)
		entry .t.l.name$i -width 20 -relief sunken -bd 2 -textvariable plotInfo(trace,$i,name)

		grid .t.l.cb$i .t.l.name$i -sticky nsew -pady 1
	}


	# Buttons
	frame .t.b
	button .t.b.cancel -text "Cancel" -command {set button 0}
	button .t.b.ok     -text "Ok"     -command {set button 1}
	pack .t.b.cancel -side right -fill y -padx 3 -pady 3
	pack .t.b.ok     -side right -fill y -padx 3 -pady 3

	pack .t.b -side bottom -anchor center
	pack .t.l -fill both -expand true

	# Grab focus, wait for a button action, the close and destroy
	set oldFocus [focus]
	grab set .t
	focus .t
	tkwait variable button
	destroy .t
	focus $oldFocus
	return button
}


# ############################################################################
#
# Menu action: open a file and read it
#
proc m_openFile {} {
   set types {
      {{CSV Files} {.csv}}
   }
   set fname [tk_getOpenFile -filetypes $types]
   
   if {$fname != ""} {
       readDataFile $fname
   }
}

# ############################################################################
#
# Menu action: plot a trace
#
proc m_plotTraces {} {
   puts "Sending to gnuplot..."
   generatePlot
   if { ![catch "exec gnuplot tekplots.cmd" msg] } {
	  puts "Loading plot graphic..."
      image create photo plot -file "tekplots.gif"
      .c config -width [image width plot] -height [image height plot]
      .c create image [expr [image width plot]/2] [expr [image height plot]/2] \
         -image plot -anchor c
   }
   puts "Done."
}

# ############################################################################
#
# Main application
#
buildGUI

if {$argc > 0} {
   set fname [lindex $argv 0]
   readDataFile $fname
}
