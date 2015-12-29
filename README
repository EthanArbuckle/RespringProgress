The principle of this is, if we know roughly how many objects SpringBoard instantiates while it loads, we can keep count of every object created and compare it to the total number that would signify SpringBoard being "done".

To do this, we need to monitor every class in SpringBoard that gets created, and keep a tally of inits. We can use the objc runtime to pull a list of classes in SpringBoard, and swizzle the init method on each one of them to a new implementation. I also restrict it to classes starting with "SB", as springboard links a lot of other things that are unnecessary to what we're doing.
Every SB* class's -init method is swizzled to an implementation that performs OSAtomicIncrement64 on a global tally, before calling the original init implementation and allowing the object to get created as normal. So as all these objects get created, they're nice enough to step up the overall -init count (and thread safe, using OSAtomic). On 9.0 on the iPhone 6s/6s+, this total number ends up being almost _exactly_ ```10^7```. Three runs, one after another (```9581247```, ```9926451```, ```9828801```).

So, i'm assuming that SpringBoard is totally launched when we have 10 million inits called. Knowing this, we start up a separate thread that watches the init counter as it increases, and compares it to our "finished" count of ```10^7```.
Something like ```((100 / 10^7) * initCount)``` will give us the guessed progress of where springboard is at.

Now swizzling all these classes when springboard starts up is fairly slow, and increased my SB load time from about 1.8 seconds to 6.2+ seconds. We can cut that down by not swizzling every single class, and only doing every nth. The more classes you skip, the faster SB loads, but the less accurate the progress guess ends up being.

I've found that swizzling every 8th class seems to be pretty good. So skipping all those classes and only swizzling every 8th is going to obviously cut down the number of inits that get called... by a factor of 8 of course.
So now we would guess the progress with ```((100 / (10^7 / 8)) * initCount)```.

That gives us a result thats pretty close to numbers we were getting when swizzling _every_ class, but now we're only taking about 2.5 seconds to fully load, way faster than the 6.2+.g