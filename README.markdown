# rbcurse-experimental

This is related to the rbcurse ncurses toolkit, for building ncurses applications.

This provides stuff I've experimented with, and tested to some extent. It can be useful stuff to build upon
or to even use if it suits your purposes. Most of this stuff has been tested with positive cases and not
with negative data. It is minimally tested.

Use for home or unimportant programs, preferable don't release these widgets for public use.

Please submit patches if you find bugs or improve upon it.

> We better hurry up and start coding, there are going to be a lot of bugs to fix. 

Contents as of time of creation of repo:

* directorylist.rb   - shows directory in a list, allowing various kinds of selection and filtering and ENTER

* directorytree.rb   - shows directory in a tree, allowing expansion

* masterdetail.rb    - master detail pattern, two widgets

* multiform.rb       - do not touch this at all. Should be nuked. It works but in order to keep
                      rbcurse simple and maintainable, I advise against using forms within forms. I've spent
                      weeks and months tracking cursor placement for forms within forms as in the old
                      tabbedpane and some old deprecated widgets.

* resultsetbrowser.rb  - I am working on database aware widgets, check dbdemo.rb in examples

* resultsettextview.rb - same as above

* rscrollform.rb    - a form that can display more objects than the window, scrolls horiz and vertically.
                      Used and tested only with single line widgets like Field, not with textviews and lists.

* stackflow.rb      - widget that allows complex weightages to be assigned to stacks and flows
                      and resizing if window dimension changes. Tested only with weightages and not
                      absolute sizes. Expects weightages to be correct. More work can go into this
                      to make it robust.

* undomanager.rb    - used in lists and textareas to support undo and redo. I've used it but 
                      its a very simple piece of code and I am not too confident how well it will stand
                      in heavy use. Certainly use it for lists and textareas in personal applications.



## Short story

Minimally tested but interesting stuff

## Long story

Use stuff here at your own risk. Most of this works, and will work in most situations but may not take care validations, extreme cases, wrong data passed.

Its tested for basic use cases. Samples should help you. Don't use in production, or release for others to use. Use for personal use if you have too. 


Feel free to fork and further develop stuff in here, or submit patches to me.

Some of this stuff may move to extras or core if its really useful and stable.

## See also

* rbcurse - <http://github.com/rkumar/rbcurse/>

* rbcurse-core - <http://github.com/rkumar/rbcurse-core/>

* rbcurse-extras - <http://github.com/rkumar/rbcurse-extras/>

## Install

    gem install rbcurse-experimental

## License

  Same as ruby license.
