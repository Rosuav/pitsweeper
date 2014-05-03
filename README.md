Pit Sweeper
===========

Minesweeper variant with guaranteed-solvable games.

Borrowing a lot of ideas from the OS/2 game "3D Logic Minesweeper", this will
guarantee that (a) every game presented is solvable with pure logic, and (b)
the top corner is empty, which is a prerequisite for the first guarantee.
Games are solved on a background thread before being presented to you; the
seed for at least one unplayed solvable game is retained across game restarts,
if possible.

A 3D gameplay option may be implemented later, much much later perhaps :)


License: MIT

Copyright (c) 2014, Chris Angelico

Permission is hereby granted, free of charge, to any person obtaining a copy of 
this software and associated documentation files (the "Software"), to deal in 
the Software without restriction, including without limitation the rights to 
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
of the Software, and to permit persons to whom the Software is furnished to do 
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all 
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
SOFTWARE.
