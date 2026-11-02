-- A command-line debugger, written on the debug API.
-- Commands: break F L, clear F L, continue, step, next, out, print NAME, where.
use debug

-- Prints the value of a variable of a frame, or says that there is none.
defn ShowVariable(frame, name)
  found = Filter(it.Name == name, frame.Vars)
  if Len(found) == 0
    Print("No variable ""$name"".")
  else
    Print("$name = $(found[1].Value)")
  end
end

-- Prints the frames of a stop, from the innermost.
defn ShowFrames(stop)
  for f in stop.Frames
    Print("  $(f.Function) ($(f.File):$(f.Line))")
  end
end

-- Is this word a command that resumes the program?
defn IsResume(word)
  word == "continue" or word == "step" or word == "next" or word == "out"
end

-- Runs one command (a list of words) that doesn't resume the program.
defn RunCommand(stop, w)
  n = Len(w)
  if n == 3 and w[1] == "break"
    debug.SetBreak(w[2], w[3])
    Print("breakpoint $(w[2]):$(w[3])")
  else if n == 3 and w[1] == "clear"
    debug.ClearBreak(w[2], w[3])
    Print("cleared $(w[2]):$(w[3])")
  else if n == 2 and w[1] == "print"
    ShowVariable(stop.Frames[1], w[2])
  else if n == 1 and w[1] == "where"
    ShowFrames(stop)
  else
    Print("Commands: break F L, clear F L, continue, step, next, out, print NAME, where.")
  end
end

-- Reads and runs commands at a stop, until one resumes the program: gives its word.
defn OnStop(stop)
  Print("stopped at $(stop.File):$(stop.Line) ($(stop.Reason))")
  while true
    line = debug.ReadLine()
    if IsMissing(line)
      return "continue"
    end
    w = debug.Words(line)
    if Len(w) > 0
      if Len(w) == 1 and IsResume(w[1])
        return w[1]
      end
      RunCommand(stop, w)
    end
  end
end
