on run
	set helper to quoted form of (POSIX path of (path to home folder) & "Library/Application Support/The Opera/opera-guard")
	set titleText to "Opera 观看守卫"
	try
		set statusLines to paragraphs of (do shell script helper & " status")
		set enteredMinutes to ""
		repeat
			set phase to item 1 of statusLines
			if phase is "started" then return
			set messageText to (item 2 of statusLines) & return & return & (item 3 of statusLines)
			if phase is "ready" or phase is "invalid" then
				set answer to display dialog messageText default answer enteredMinutes with title titleText buttons {"取消", "开始计时并打开"} default button "开始计时并打开" cancel button "取消" with icon note
				set enteredMinutes to text returned of answer
				set statusLines to paragraphs of (do shell script helper & " start " & quoted form of enteredMinutes)
			else
				display dialog messageText with title titleText buttons {"知道了"} default button "知道了" with icon note
				return
			end if
		end repeat
	on error errorText number errorNumber
		if errorNumber is -128 then return
		display alert "暂时无法开启 Opera" message errorText as warning
	end try
end run
