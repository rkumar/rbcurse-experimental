#!/usr/bin/env ruby
# ----------------------------------------------------------------------------- #
#         File: tablewidget.rb
#  Description: A tabular widget based on textpad
#       Author: rkumar http://github.com/rkumar/rbcurse/
#         Date: 2013-03-29 - 20:07
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2013-04-23 16:19
# ----------------------------------------------------------------------------- #
#   tablewidget.rb  Copyright (C) 2012-2013 rahul kumar

require 'logger'
require 'rbcurse'
require 'rbcurse/core/widgets/textpad'

## 
# The motivation to create yet another table widget is because tabular_widget
# is based on textview etc which have a lot of complex processing and rendering
# whereas textpad is quite simple. It is easy to just add one's own renderer
# making the code base simpler to understand and maintain.
# TODO
#   _ compare to tabular_widget and see what's missing
#   _ filtering rows without losing data
#   . selection stuff
#   x test with resultset from sqlite to see if we can use Array or need to make model
#     should we use a datamodel so resultsets can be sent in, what about tabular
#   _ header to handle events ?
#
#
module RubyCurses
  # column data, one instance for each column
  # index is the index in the data of this column. This index will not change.
  # Order of printing columns is determined by the ordering of the objects.
  class ColumnInfo < Struct.new(:name, :index, :offset, :width, :align, :hidden, :attrib, :color, :bgcolor)
  end
  # a structure that maintains position and gives
  # next and previous taking max index into account.
  # it also circles. Can be used for traversing next component
  # in a form, or container, or columns in a table.
  class Circular < Struct.new(:max_index, :current_index)
    attr_reader :last_index
    attr_reader :current_index
    def initialize  m, c=0
      raise "max index cannot be nil" unless m
      @max_index = m
      @current_index = c
      @last_index = c
    end
    def next
      @last_index = @current_index
      if @current_index + 1 > @max_index
        @current_index = 0
      else
        @current_index += 1
      end
    end
    def previous
      @last_index = @current_index
      if @current_index - 1 < 0
        @current_index = @max_index
      else
        @current_index -= 1
      end
    end
    def is_last?
      @current_index == @max_index
    end
  end

    # This is our default table row sorter.
    # It does a multiple sort and allows for reverse sort also.
    # It's a pretty simple sorter and uses sort, not sort_by.
    # Improvements welcome.
    # Usage: provide model in constructor or using model method
    # Call toggle_sort_order(column_index) 
    # Call sort. 
    # Currently, this sorts the provided model in-place. Future versions
    # may maintain a copy, or use a table that provides a mapping of model to result.
    # # TODO check if column_sortable
    class DefaultTableRowSorter
      attr_reader :sort_keys
      # model is array of data
      def initialize data_model=nil
        self.model = data_model
        @columns_sort = []
        @sort_keys = nil
      end
      def model=(model)
        @model = model
        @sort_keys = nil
      end
      def sortable colindex, tf
        @columns_sort[colindex] = tf
      end
      def sortable? colindex
        return false if @columns_sort[colindex]==false
        return true
      end
      # should to_s be used for this column
      def use_to_s colindex
        return true # TODO
      end
      # sorts the model based on sort keys and reverse flags
      # @sort_keys contains indices to sort on
      # @reverse_flags is an array of booleans, true for reverse, nil or false for ascending
      def sort
        return unless @model
        return if @sort_keys.empty?
        $log.debug "TABULAR SORT KEYS #{sort_keys} "
        # first row is the header which should remain in place
        # We could have kept column headers separate, but then too much of mucking around
        # with textpad, this way we avoid touching it
        header = @model.delete_at 0
        begin
          # next line often can give error "array within array" - i think on date fields that 
          #  contain nils
        @model.sort!{|x,y| 
          res = 0
          @sort_keys.each { |ee| 
            e = ee.abs-1 # since we had offsetted by 1 earlier
            abse = e.abs
            if ee < 0
              res = y[abse] <=> x[abse]
            else
              xx = x[e]
              yy = y[e]
              if xx.nil? && yy.nil?
                res = 0
              elsif xx.nil?
                res = -1
              elsif yy.nil?
                res = 1
              else
              res = x[e] <=> y[e]
              end
            end
            break if res != 0
          }
          res
        }
        ensure
          @model.insert 0, header if header
        end
      end
      # toggle the sort order if given column offset is primary sort key
      # Otherwise, insert as primary sort key, ascending.
      def toggle_sort_order index
        index += 1 # increase by 1, since 0 won't multiple by -1
        # internally, reverse sort is maintained by multiplying number by -1
        @sort_keys ||= []
        if @sort_keys.first && index == @sort_keys.first.abs
          @sort_keys[0] *= -1 
        else
          @sort_keys.delete index # in case its already there
          @sort_keys.delete(index*-1) # in case its already there
          @sort_keys.unshift index
          # don't let it go on increasing
          if @sort_keys.size > 3
            @sort_keys.pop
          end
        end
      end
      def set_sort_keys list
        @sort_keys = list
      end
    end #class
  #
  # TODO see how jtable does the renderers and columns stuff.
  #
  # perhaps we can combine the two but have different methods or some flag
  # that way oter methods can be shared
  class DefaultTableRenderer

    # source is the textpad or extending widget needed so we can call show_colored_chunks
    # if the user specifies column wise colors
    def initialize source
      @source = source
      @y = '|'
      @x = '+'
      @coffsets = []
      @header_color = :red
      @header_bgcolor = :white
      @header_attrib = NORMAL
      @color = :white
      @bgcolor = :black
      @color_pair = $datacolor
      @attrib = NORMAL
      @_check_coloring = nil
    end
    def header_colors fg, bg
      @header_color = fg
      @header_bgcolor = bg
    end
    def header_attrib att
      @header_attrib = att
    end
    # set fg and bg color of content rows, default is $datacolor (white on black).
    def content_colors fg, bg
      @color = fg
      @bgcolor = bg
      @color_pair = get_color($datacolor, fg, bg)
    end
    def content_attrib att
      @attrib = att
    end
    def column_model c
      @chash = c
    end
    ##
    # Takes the array of row data and formats it using column widths
    # and returns a string which is used for printing
    #
    # TODO return an array so caller can color columns if need be
    def convert_value_to_text r  
      str = []
      fmt = nil
      field = nil
      # we need to loop through chash and get index from it and get that row from r
      #r.each_with_index { |e, i| 
        #c = @chash[i]
      #@chash.each_with_index { |c, i| 
        #next if c.hidden
      each_column {|c,i|
        e = r[c.index]
        w = c.width
        l = e.to_s.length
        # if value is longer than width, then truncate it
        if l > w
          fmt = "%.#{w}s "
        else
          case c.align
          when :right
            fmt = "%#{w}s "
          else
            fmt = "%-#{w}s "
          end
        end
        field = fmt % e
        # if we really want to print a single column with color, we need to print here itself
        # each cell. If we want the user to use tmux formatting in the column itself ...
        # FIXME - this must not be done for headers.
        #if c.color
          #field = "#[fg=#{c.color}]#{field}#[/end]"
        #end
        str << field
      }
      return str
    end
    #
    # @param pad for calling print methods on
    # @param lineno the line number on the pad to print on
    # @param text data to print
    def render pad, lineno, str
      #lineno += 1 # header_adjustment
      return render_header pad, lineno, 0, str if lineno == 0
      #text = str.join " | "
      #text = @fmstr % str
      text = convert_value_to_text str
      if @_check_coloring
        $log.debug "XXX:  INSIDE COLORIIN"
        text = colorize pad, lineno, text
        return
      end
      # check if any specific colors , if so then print colors in a loop with no dependence on colored chunks
      # then we don't need source pointer
      text = text.join
      $log.debug "XXX:  NOTINSIDE COLORIIN"
      #if text.index "#["
        #require 'rbcurse/core/include/chunk'
        #@parser ||= Chunks::ColorParser.new :tmux
        #text = @parser.convert_to_chunk text
        #FFI::NCurses.wmove pad, lineno, 0
        #@source.show_colored_chunks text, nil, nil
        #return
      #end
      # FIXME why repeatedly getting this colorpair
      cp = @color_pair
      att = @attrib
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)

    end
    def render_header pad, lineno, col, columns
      # I could do it once only but if user sets colors midway we can check once whenvever
      # repainting
      check_colors #if @_check_coloring.nil?
      #text = columns.join " | "
      #text = @fmstr % columns
      text = convert_value_to_text columns
      text = text.join
      bg = @header_bgcolor
      fg = @header_color
      att = @header_attrib
      #cp = $datacolor
      cp = get_color($datacolor, fg, bg)
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, col, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
    end
    # check if we need to individually color columns or we can do the entire
    # row in one shot
    def check_colors
      each_column {|c,i|
      #@chash.each_with_index { |c, i| 
        #next if c.hidden
        if c.color || c.bgcolor || c.attrib
          @_check_coloring = true
          return
        end
        @_check_coloring = false
      }
    end
    def each_column
      @chash.each_with_index { |c, i| 
        next if c.hidden
        yield c,i if block_given?
      }
    end
  def colorize pad, lineno, r
    # the incoming data is already in the order of display based on chash,
    # so we cannot run chash on it again, so how do we get the color info
    _offset = 0
    # we need to get coffsets here FIXME
    #@chash.each_with_index { |c, i| 
      #next if c.hidden
    each_column {|c,i|
      text = r[i]
      color = c.color
      bg = c.bgcolor
      if color || bg
        cp = get_color(@color_pair, color || @color, bg || @bgcolor)
      else
        cp = @color_pair
      end
      att = c.attrib || @attrib
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, _offset, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      _offset += text.length
    }
  end
  end

  # If we make a pad of the whole thing then the columns will also go out when scrolling
  # So then there's no point storing columns separately. Might as well keep in content
  # so scrolling works fine, otherwise textpad will have issues scrolling.
  # Making a pad of the content but not column header complicates stuff,
  # do we make a pad of that, or print it like the old thing.
  class TableWidget < TextPad

    dsl_accessor :print_footer
    #attr_reader :columns
    attr_accessor :table_row_sorter

    def initialize form = nil, config={}, &block

      # hash of column info objects, for some reason a hash and not an array
      @chash = []
      # chash should be an array which is basically the order of rows to be printed
      #  it contains index, which is the offset of the row in the data @content
      #  When printing we should loop through chash and get the index in data
      #
      # should be zero here, but then we won't get textpad correct
      @_header_adjustment = 0 #1
      @col_min_width = 3

      super
      bind_key(?w, "next column") { self.next_column }
      bind_key(?b, "prev column") { self.prev_column }
      bind_key(?-, "contract column") { self.contract_column }
      bind_key(?+, "expand column") { self.expand_column }
      bind_key(?=, "expand column to width") { self.expand_column_to_width }
      bind_key(?\M-=, "expand column to width") { self.expand_column_to_max_width }
    end
    
    # retrieve the column info structure for the given offset. The offset
    # pertains to the visible offset not actual offset in data model. 
    # These two differ when we move a column.
    # @return ColumnInfo object containing width align color bgcolor attrib hidden
    def get_column index
      return @chash[index] if @chash[index]
      # create a new entry since none present
      c = ColumnInfo.new
      c.index = index
      @chash[index] = c
      return c
    end
    ## 
    # returns collection of ColumnInfo objects
    def column_model
      @chash
    end

    # calculate pad width based on widths of columns
    def content_cols
      total = 0
      #@chash.each_pair { |i, c| 
      #@chash.each_with_index { |c, i| 
        #next if c.hidden
      each_column {|c,i|
        w = c.width
        # if you use prepare_format then use w+2 due to separator symbol
        total += w + 1
      }
      return total
    end

    # 
    # This calculates and stores the offset at which each column starts.
    # Used when going to next column or doing a find for a string in the table.
    # TODO store this inside the hash so it's not calculated again in renderer
    #
    def _calculate_column_offsets
      @coffsets = []
      total = 0

      #@chash.each_pair { |i, c| 
      #@chash.each_with_index { |c, i| 
        #next if c.hidden
      each_column {|c,i|
        w = c.width
        @coffsets[i] = total
        c.offset = total
        # if you use prepare_format then use w+2 due to separator symbol
        total += w + 1
      }
    end
    # Convert current cursor position to a table column
    # calculate column based on curpos since user may not have
    # user w and b keys (:next_column)
    # @return [Fixnum] column index base 0
    def _convert_curpos_to_column  #:nodoc:
      _calculate_column_offsets unless @coffsets
      x = 0
      @coffsets.each_with_index { |i, ix| 
        if @curpos < i 
          break
        else 
          x += 1
        end
      }
      x -= 1 # since we start offsets with 0, so first auto becoming 1
      return x
    end
    # jump cursor to next column
    # TODO : if cursor goes out of view, then pad should scroll right or left and down
    def next_column
      # TODO take care of multipliers
      _calculate_column_offsets unless @coffsets
      c = @column_pointer.next
      cp = @coffsets[c] 
      #$log.debug " next_column #{c} , #{cp} "
      @curpos = cp if cp
      down() if c < @column_pointer.last_index
    end
    # jump cursor to previous column
    # TODO : if cursor goes out of view, then pad should scroll right or left and down
    def prev_column
      # TODO take care of multipliers
      _calculate_column_offsets unless @coffsets
      c = @column_pointer.previous
      cp = @coffsets[c] 
      #$log.debug " prev #{c} , #{cp} "
      @curpos = cp if cp
      up() if c > @column_pointer.last_index
    end
    def expand_column
      x = _convert_curpos_to_column
      w = get_column(x).width
      column_width x, w+1 if w
      @coffsets = nil
      fire_dimension_changed
    end
    def expand_column_to_width w=nil
      x = _convert_curpos_to_column
      unless w
        # expand to width of current cell
        s = @content[@current_index][x]
        w = s.to_s.length + 1
      end
      column_width x, w
      @coffsets = nil
      fire_dimension_changed
    end
    # find the width of the longest item in the current columns and expand the width
    # to that.
    def expand_column_to_max_width
      x = _convert_curpos_to_column
      w = calculate_column_width x
      expand_column_to_width w
    end
    def contract_column
      x = _convert_curpos_to_column
      w = get_column(x).width 
      return if w <= @col_min_width
      column_width x, w-1 if w
      @coffsets = nil
      fire_dimension_changed
    end

    #def method_missing(name, *args)
    #@tp.send(name, *args)
    #end
    #
    # supply a custom renderer that implements +render()+
    # @see render
    def renderer r
      @renderer = r
    end

    ##
    # Set column titles with given array of strings.
    # NOTE: This is only required to be called if first row of file or content does not contain
    # titles. In that case, this should be called before setting the data as the array passed
    # is appended into the content array.
    #
    def columns=(array)
      @_header_adjustment = 1
      # I am eschewing using a separate field for columns. This is simpler for textpad.
      # We always assume first row is columns.
      #@columns = array
      # should we just clear column, otherwise there's no way to set the whole thing with new data
      # but then if we need to change columns what do it do, on moving or hiding a column ?
      # Maybe we need a separate clear method or remove_all TODO
      @content ||= []
      @content << array
      # This needs to go elsewhere since this method will not be called if file contains
      # column titles as first row.
      _init_model array
    end
    alias :headings= :columns=

    # returns array of column names as Strings
    def columns
      @content[0]
    end

    # size each column based on widths of this row of data.
    # Only changed width if no width for that column
    def _init_model array
      array.each_with_index { |c,i| 
        # if columns added later we could be overwriting the width
        c = get_column(i)
        c.width ||= 10
      }
      # maintains index in current pointer and gives next or prev
      @column_pointer = Circular.new array.size()-1
    end
    def model_row index
      array = @content[index]
      array.each_with_index { |c,i| 
        # if columns added later we could be overwriting the width
        ch = get_column(i)
        ch.width = c.to_s.length + 2
      }
      # maintains index in current pointer and gives next or prev
      @column_pointer = Circular.new array.size()-1
    end

    ## 
    # insert entire database in one shot
    # WARNING: overwrites columns if put there, should contain columns already as in CSV data
    # @param lines is an array or arrays
    def text lines, fmt=:none
      _init_model lines[0]
      fire_dimension_changed
      super
    end

    ##
    # set column array and data array in one shot
    # Erases any existing content
    def resultset columns, data
      @content = []
      _init_model columns
      @content << columns
      @_header_adjustment = 1
      
      @content.concat( data)
      fire_dimension_changed
    end


      ## add a row to the table
    def add array
      unless @content
        # columns were not added, this most likely is the title
        @content ||= []
        _init_model array
      end
      @content << array
      fire_dimension_changed
      self
    end
    def delete_at ix
      return unless @content
      fire_dimension_changed
      @content.delete_at ix
    end
    alias :<< :add
    # convenience method to set width of a column
    # @param index of column
    # @param width
    # For setting other attributes, use get_column(index)
    def column_width colindex, width
      get_column(colindex).width = width
      _invalidate_width_cache
    end
    # convenience method to set alignment of a column
    # @param index of column
    # @param align - :right (any other value is taken to be left)
    def column_align colindex, align
      get_column(colindex).align = align
    end
    # convenience method to hide or unhide a column
    # Provided since column offsets need to be recalculated in the case of a width
    # change or visibility change
    def column_hidden colindex, hidden
      get_column(colindex).hidden = hidden
      _invalidate_width_cache
    end
    # http://www.opensource.apple.com/source/gcc/gcc-5483/libjava/javax/swing/table/DefaultTableColumnModel.java
    def _invalidate_width_cache    #:nodoc:
      @coffsets = nil
    end
    ## 
    # should all this move into table column model or somepn
    # move a column from offset ix to offset newix
    def move_column ix, newix
      acol = @chash.delete_at ix 
      @chash.insert newix, acol
      _invalidate_width_cache
      #tmce = TableColumnModelEvent.new(ix, newix, self, :MOVE)
      #fire_handler :TABLE_COLUMN_MODEL_EVENT, tmce
    end
    def add_column tc
      raise "to figure out add_column"
      _invalidate_width_cache
    end
    def remove_column tc
      raise "to figure out add_column"
      _invalidate_width_cache
    end
    def calculate_column_width col, maxrows=99
      ret = 3
      ctr = 0
      @content.each_with_index { |r, i| 
        #next if i < @toprow # this is also a possibility, it checks visible rows
        break if ctr > maxrows
        ctr += 1
        #next if r == :separator
        c = r[col]
        x = c.to_s.length
        ret = x if x > ret
      }
      ret
    end
    ##
    # refresh pad onto window
    # overrides super
    def padrefresh
      top = @window.top
      left = @window.left
      sr = @startrow + top
      sc = @startcol + left
      # first do header always in first row
      retval = FFI::NCurses.prefresh(@pad,0,@pcol, sr , sc , 2 , @cols+ sc );
      # now print rest of data
      # h is header_adjustment
      h = 1 
      retval = FFI::NCurses.prefresh(@pad,@prow + h,@pcol, sr + h , sc , @rows + sr  , @cols+ sc );
      $log.warn "XXX:  PADREFRESH #{retval}, #{@prow}, #{@pcol}, #{sr}, #{sc}, #{@rows+sr}, #{@cols+sc}." if retval == -1
      # padrefresh can fail if width is greater than NCurses.COLS
    end

    def create_default_sorter
      raise "Data not sent in." unless @content
      @table_row_sorter = DefaultTableRowSorter.new @content
    end
    def header_row?
      @prow == 0
    end

    def fire_action_event
      if header_row?
        if @table_row_sorter
          x = _convert_curpos_to_column
          c = @chash[x]
          # convert to index in data model since sorter only has data_model
          index = c.index
          @table_row_sorter.toggle_sort_order index
          @table_row_sorter.sort
          fire_dimension_changed
        end
      end
      super
    end
    ## 
    # Find the next row that contains given string
    # Overrides textpad since each line is an array
    # NOTE does not go to next match within row
    # NOTE: FIXME ensure_visible puts prow = current_index so in this case, the header
    #   overwrites the matched row.
    # @return row and col offset of match, or nil
    # @param String to find
    def next_match str
      _calculate_column_offsets unless @coffsets
      first = nil
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      @content.each_with_index do |fields, ix|
        #col = line.index str
        #fields.each_with_index do |f, jx|
        #@chash.each_with_index do |c, jx|
          #next if c.hidden
        each_column do |c,jx|
          f = fields[c.index]
          # value can be numeric
          col = f.to_s.index str
          if col
            col += @coffsets[jx] 
            first ||= [ ix, col ]
            if ix > @current_index
              return [ix, col]
            end
          end
        end
      end
      return first
    end
    # yields each column to caller method
    # for true returned, collects index of row into array and returns the array
    # @returns array of indices which can be empty
    # Value yielded can be fixnum or date etc
    def matching_indices 
      raise "block required for matching_indices" unless block_given?
      @indices = []
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      @content.each_with_index do |fields, ix|
        flag = yield ix, fields
        if flag
          @indices << ix 
        end
      end
      $log.debug "XXX:  INDICES found #{@indices}"
      if @indices.count > 0
        fire_dimension_changed
        init_vars
      else
        @indices = nil
      end
      #return @indices
    end
    def clear_matches
      # clear previous match so all data can show again
      if @indices && @indices.count > 0
        fire_dimension_changed
        init_vars
      end
      @indices = nil
    end
    ## 
    # Ensure current row is visible, if not make it first row
    #  This overrides textpad due to header_adjustment, otherwise
    #  during next_match, the header overrides the found row.
    # @param current_index (default if not given)
    #
    def ensure_visible row = @current_index
      unless is_visible? row
          @prow = @current_index - @_header_adjustment
      end
    end
    #
    # yields non-hidden columns (ColumnInfo) and the offset/index
    # This is the order in which columns are to be printed
    def each_column
      @chash.each_with_index { |c, i| 
        next if c.hidden
        yield c,i if block_given?
      }
    end
    def render_all
      if @indices && @indices.count > 0
        @indices.each_with_index do |ix, jx|
          render @pad, jx, @content[ix]
        end
      else
        @content.each_with_index { |line, ix|
          #FFI::NCurses.mvwaddstr(@pad,ix, 0, @content[ix])
          render @pad, ix, line
        }
      end
    end

  end # class TableWidget

  ##
  # Handles selection of items in a list or table or tree that uses stable indices.
  # Indexes are in the order they were places, not sorted.
  # This is just a wrapper over an array, except that it fires an event so users can bind
  # to row selection and deselection
  # TODO - fire events to listeners
  #
  class ListSelectionModel
    ##
    # obj is the source object, I am wondering whether i need it or not
    def initialize component
      @obj = component
      @selected_indices = []
    end
    def toggle_row_selection crow
      if is_row_selected? crow
        unselect crow
      else
        select crow
      end
    end
    def select ix
      @selected_indices << ix
      _fire_event ix, ix, :INSERT
    end
    def unselect ix
      @selected_indices.delete ix
      _fire_event ix, ix, :DELETE
    end
    alias :add_to_selection :select
    alias :remove_from_selection :unselect
    def clear_selection
      @selected_indices = []
      _fire_event 0, 0, :CLEAR
    end
    def is_row_selected? crow
      @selected_indices.include? crow
    end
    def is_selection_empty?
      return @selected_indices.empty?
    end
    # if row deleted in list, then synch with list
    # (No listeners  are informed)
    def remove_index crow
      @selected_indices.delete crow
    end
    def _fire_event firsti, lasti, event
      lse = ListSelectionEvent.new(firsti, lasti, self, event)
      fire_handler :LIST_SELECTION_EVENT, lse
    end

    def select_all
      # how do we do this since we don't know what the indices are. 
      # What is the user using as identifier?
    end
     
    # returns a list of selected indices in the same order as added
    def selected_rows
      @selected_indices
    end
  end # class
  class ListSelectionEvent < Struct.new(:firstrow, :lastrow, :source, :type)
  end
end # module
