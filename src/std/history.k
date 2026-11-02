-- Undo and redo: values don't change, so a history only keeps the ones it saw.

-- A history that starts at a state and keeps at most limit past states.
Of(state, limit = 1000) = {Past: [], Present: state, Future: [], Limit: limit}
-- The state now.
--
--   Current(Of(1)) --> 1
Current(h) = h.Present

-- A history with a new state, which forgets what could be redone.
defn Record(state, h)
  past = Append(h.Present, h.Past)
  kept = if Len(past) > h.Limit Skip(1, past) else past end
  {Past: kept, Present: state, Future: [], Limit: h.Limit}
end

-- Is there a past state to go back to?
--
--   CanUndo(Of(1)) --> false
CanUndo(h) = Len(h.Past) > 0
-- Is there an undone state to go forward to?
--
--   CanRedo(Of(1)) --> false
CanRedo(h) = Len(h.Future) > 0

-- The history one state back, or the same one if there is none.
--
--   Current(Undo(Record(2, Of(1)))) --> 1
defn Undo(h)
  if not CanUndo(h)
    return h
  end
  n = Len(h.Past)
  {Past: Take(n - 1, h.Past), Present: h.Past[n], Future: Append(h.Present, h.Future), Limit: h.Limit}
end

-- The history one state forward after an undo, or the same one if there is none.
--
--   Current(Redo(Undo(Record(2, Of(1))))) --> 2
defn Redo(h)
  if not CanRedo(h)
    return h
  end
  n = Len(h.Future)
  {Past: Append(h.Present, h.Past), Present: h.Future[n], Future: Take(n - 1, h.Future), Limit: h.Limit}
end
