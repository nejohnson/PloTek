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

# Global data
::struct::matrix data

set monochrome 0

# Plot size
#  small  = 640 x 480
#  medium = 1200 x 800
#  large  = 1920 x 1280
#set plotSize "640,480"
set plotSize "1200,800"
#set plotSize "1920,1280"

# ############################################################################
#
# Load the CSV data file into memory
#
proc readDataFile {fname} {
	global data
	
	puts "Reading $fname ..."
	set chan [open $fname]
	csv::read2matrix $chan data  , auto
	close $chan
	puts "Done."
}

# ############################################################################
#
# Scan a data file enumerating the scope traces
#
proc scanDataFile {} {
	global data
	global plotList
	global plotEn
	
	set plotList {}
	set trc 0
	set i 0
	
	puts "Scanning data..."
	for {set c 0} {$c < [data columns]} {incr c 6} {
		set name [data get cell [expr $c + 1] 6]
		puts "  found dataset $name"
		if {[string match "Glitch*" $name] == 0} {
			.menubar.plot add checkbutton -label "$i: $name" -variable plotEn($trc)
			set plotEn($trc) 0
			lappend plotList $trc 
			puts "  $trc: adding plot"
			incr i
		}
		incr trc
	}
	puts "Done."
}

# ############################################################################
#
# Process a single trace
#
proc generateScopeTraces {title} {
	global data
	global plotList
	global plotEn
	global monochrome
	global plotSize

	puts "Generating Scope Traces..."

	set i 0
	set ofile [open "tekplots.cmd" w]
	set rows [data rows]

	set plotcommand ""

	foreach l $plotList {
		set enabled $plotEn($l)
		set tracenum $l
		set base [expr $tracenum * 6]

		# Extract trace parameters
		set params [data get rect [expr $base + 1] 0 [expr $base + 1] 15]
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

			if {$title != ""} {
				#puts "set title \"[data get cell [expr $base + 1] 6] ([data get cell [expr $base + 1] 16])\""
				puts $ofile "set title \"$title\""
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
			set div [expr int($div)]
			puts $ofile "set ylabel \"$div $mult$vertUnits/div\""
			puts $ofile "set yrange \[ -[expr $vertScale * 4] : [expr $vertScale * 4]\]"
			puts $ofile "set ytics $vertScale format \"\""

			puts $ofile "set grid xtics ytics"

			puts $ofile "set terminal gif size $plotSize"
			puts $ofile "set output \"tekplots.gif\""
		}

		if {$enabled} {
			puts $ofile "\$ScopeTrace$i << EOD"
			for {set row 0} {$row < $rows} {incr row} {
				set point [data get rect [expr $base + 3] $row [expr $base + 4] $row]
				puts $ofile [format "%.6f %.6f %.6f" [lindex [lindex $point 0] 0] [expr [lindex [lindex $point 0] 1] + $vertScale * $yZero] $vertOffset]
			}
			puts $ofile "EOD"
			set colour ""
			if {$monochrome} {
				set colour "lc \"black\""
			}
			set thisplot " \$ScopeTrace$i using 1:2 with lines $colour title \"$source\" at beginning,"
			# \$ScopeTrace$i using 1:3 with lines title \"\" $colour, "
			append plotcommand $thisplot
		}
		incr i
	}

	puts $ofile "plot $plotcommand"

	puts "Done."
   
   close $ofile
}

# ############################################################################
#
# Set up the GUI
#
proc buildGUI {} {
	global monochrome

   . config -menu .menubar
   menu .menubar

   .menubar add cascade -label "File" -menu .menubar.file
   menu .menubar.file -tearoff no
   .menubar.file add command -label "Open" -command { m_openFile }
   .menubar.file add separator
   .menubar.file add command -label "Exit" -command { exit }

   .menubar add cascade -label "Traces" -menu .menubar.plot
   menu .menubar.plot -tearoff no

   .menubar add checkbutton -label "Monochrome" -variable monochrome
   
   .menubar add command -label "PLOT!" -command { m_plotTraces }
   
   .menubar add cascade -label "Help" -menu .menubar.help
   menu .menubar.help -tearoff no
   .menubar.help add command -label "About" -command {}

   canvas .c
   pack .c -expand true -fill both -side top -anchor n
}

# ############################################################################
#
# Menu action: open a file and read it
#
proc m_openFile {} {
   global fname
   
   set types {
      {{CSV Files} {.csv}}
   }
   set fname [tk_getOpenFile -filetypes $types]
   
   if {$fname != ""} {
      readDataFile $fname
      scanDataFile
   }
}

# ############################################################################
#
# Menu action: plot a trace
#
proc m_plotTraces {} {
	puts "Sending to gnuplot..."
   generateScopeTraces ""
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
   scanDataFile
}
