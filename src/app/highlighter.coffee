_ = require 'underscore'
ScreenLineFragment = require 'screen-line-fragment'
EventEmitter = require 'event-emitter'
Token = require 'token'

module.exports =
class Highlighter
  @idCounter: 1
  buffer: null
  screenLines: []

  constructor: (@buffer, @tabText) ->
    @id = @constructor.idCounter++
    @screenLines = @buildLinesForScreenRows('start', 0, @buffer.getLastRow())
    @buffer.on "change.highlighter#{@id}", (e) => @handleBufferChange(e)

  handleBufferChange: (e) ->
    oldRange = e.oldRange.copy()
    newRange = e.newRange.copy()
    previousState = @screenLines[oldRange.end.row].state # used in spill detection below

    startState = @screenLines[newRange.start.row - 1]?.state or 'start'
    @screenLines[oldRange.start.row..oldRange.end.row] =
      @buildLinesForScreenRows(startState, newRange.start.row, newRange.end.row)

    # spill detection
    # compare scanner state of last re-highlighted line with its previous state.
    # if it differs, re-tokenize the next line with the new state and repeat for
    # each line until the line's new state matches the previous state. this covers
    # cases like inserting a /* needing to comment out lines below until we see a */
    for row in [newRange.end.row...@buffer.getLastRow()]
      break if @screenLines[row].state == previousState
      nextRow = row + 1
      previousState = @screenLines[nextRow].state
      @screenLines[nextRow] = @buildLineForScreenRow(@screenLines[row].state, nextRow)

    # if highlighting spilled beyond the bounds of the textual change, update
    # the pre and post range to reflect area of highlight changes
    if nextRow > newRange.end.row
      oldRange.end.row += (nextRow - newRange.end.row)
      newRange.end.row = nextRow
      endColumn = @buffer.lineForRow(nextRow).length
      newRange.end.column = endColumn
      oldRange.end.column = endColumn

    @trigger("change", {oldRange, newRange})

  buildLinesForScreenRows: (startState, startRow, endRow) ->
    state = startState
    for row in [startRow..endRow]
      screenLine = @buildLineForScreenRow(state, row)
      state = screenLine.state
      screenLine

  buildLineForScreenRow: (state, row) ->
    tokenizer = @buffer.getMode().getTokenizer()
    line = @buffer.lineForRow(row)
    {tokens, state} = tokenizer.getLineTokens(line, state)
    tokenObjects = []
    for tokenProperties in tokens
      token = new Token(tokenProperties)
      tokenObjects.push(token.breakOutTabCharacters(@tabText)...)
    text = _.pluck(tokenObjects, 'value').join('')
    new ScreenLineFragment(tokenObjects, text, [1, 0], [1, 0], { state })

  lineForScreenRow: (row) ->
    @screenLines[row]

  lineForRow: (row) ->
    @lineForScreenRow(row)

  linesForScreenRows: (startRow, endRow) ->
    @screenLines[startRow..endRow]

  destroy: ->
    @buffer.off ".highlighter#{@id}"

_.extend(Highlighter.prototype, EventEmitter)
