/* Pitsweeper - Minesweeper variant with guaranteed-solvable games.

Game mode consists of four numbers (xsize, ysize, pits, ntokens). The last one
is ignored other than in hideseek mode.
Playing style is one of these:
"gentle" - nothing ends the game except actual completion
"classic" - sweeping a pit ends the game, flagging a non-pit doesn't
"logic" - sweeping a pit or flagging a non-pit ends the game
"hideseek" - sweeping a pit doesn't end a game, and you can sweep a flagged pit

In hideseek mode, re-sweeping a swept pit may be important, but won't affect
your score. In all modes, your score will be a tuple ({pits swept, time taken}),
lower is better. Obviously classic and logic mode will always have the first
figure at 0, but the other two won't.

Limits:
* pits <= xsize*ysize/3; possibly /4 for safety, as this AI solver is slower
  than the OS/2 3D Mines solver, so finding solvable games can take a very
  long time if there are a lot of pits.
* ntokens <= pits/2? Definitely ntokens < pits.
*/

array(array(int)) curgame; //Game field displayed to user
array(array(int)) nextgame; //Game field ready to display
array(array(GTK2.Button)) buttons;
array(int) gamemode=({8,8,8,4}); //xsize, ysize, pits, ntokens - what the user asked for
array(int) nextmode; //gamemode of the nextgame
int pitfalls,starttime;
string playstyle="classic";
int gameover; //When 1, no gameplay is possible.
array(int) tokens;

Thread.Thread genthread; //Will always (post-initialization) exist, but might be a terminated thread.

GTK2.Window mainwindow;
GTK2.Label msg;
GTK2.Table tb;

class region(int pits)
{
	multiset(int) unk=(<>); //Has (x<<8|y) for each unknown in the region
	//Keeps track of the number of pits spread between these points. If pits==sizeof(unk), all points can be flagged; if pits==0, all can be safely dug.
	void addfield(array(array(int)) area,int x,int y)
	{
		if (x>=0 && x<sizeof(area) && y>=0 && y<sizeof(area[0]))
		{
			if (area[x][y]==9 || area[x][y]>=20) --pits;
			else if (area[x][y]>=10) unk[x<<8|y]=1;
		}
	}
	region load(array(array(int)) area,int x,int y)
	{
		addfield(area,x,y-1);
		addfield(area,x+1,y-1);
		addfield(area,x+1,y);
		addfield(area,x+1,y+1);
		addfield(area,x,y+1);
		addfield(area,x-1,y+1);
		addfield(area,x-1,y);
		addfield(area,x-1,y-1);
		return this;
	}
	string _sprintf(int type) {return pits+" pits at "+map(indices(unk),lambda(int x) {return sprintf("%c%d",(x>>8)+'A',(x&255)+1);})*", ";}
};

region hint(array(array(int)) area)
{
	array(region) regions=({ });
	foreach (area;int x;array(int) col) foreach (col;int y;int npits)
	{
		if (npits>8) continue;
		region r=region(npits)->load(area,x,y);
		if (!sizeof(r->unk)) continue;
		if (!r->pits || r->pits==sizeof(r->unk)) return r;
		else regions+=({r});
	}
	foreach (values(regions),region r)
	{
		if (!r->pits || r->pits==sizeof(r->unk)) return r;
		foreach (values(regions),region rr)
		{
			//Attempt to subtract rr from r
			region diff=region(r->pits-rr->pits);
			if (!sizeof(diff->unk=r->unk-rr->unk)) continue; //Don't add a null region if the regions are completely identical (probably r==rr)
			if (sizeof(rr->unk-r->unk)) continue; //Regions don't perfectly overlap.
			if (!diff->pits || diff->pits==sizeof(diff->unk)) return diff;
			else regions+=({diff});
		}
	}
}

array(array(int)) generate(array(int) mode)
{
	[int xsize,int ysize,int pits,int ntokens]=mode;
	int start=time();
	int tries=0;
	while (1)
	{
		++tries;
		array(array(int)) area=allocate(xsize,allocate(ysize));
		//Dig some pits.
		for (int i=0;i<pits;++i)
		{
			int x=random(xsize),y=random(ysize);
			if ((x<2 && y<2) || area[x][y]) {--i; continue;}
			area[x][y]=19;
		}
		//Now fall into them :)
		function haspit=lambda(int x,int y)
		{
			return (x>=0 && x<sizeof(area) && y>=0 && y<sizeof(area[0]) && area[x][y]==19);
		};
		foreach (area;int x;array(int) col) foreach (col;int y;int cell)
		{
			if (area[x][y]!=19) area[x][y]=10
				+haspit(x-1,y)
				+haspit(x-1,y+1)
				+haspit(x,y+1)
				+haspit(x+1,y+1)
				+haspit(x+1,y)
				+haspit(x+1,y-1)
				+haspit(x,y-1)
				+haspit(x-1,y-1)
			;
		}
		//return area; //Early abort if you want non-guaranteed games
		//Attempt to solve the puzzle. If we succeed, return, otherwise continue.
		area[0][0]-=10; //Dig the first hole.
		while (region r=hint(area)) foreach (indices(r->unk),int xy) if (area[xy>>8][xy&255]>9) area[xy>>8][xy&255]-=10;
		int done=1;
		foreach (area,array(int) col) foreach (col,int cell) if (cell>9) {done=0; break;}
		if (!done) continue;
		for (int x=0;x<sizeof(area);++x) for (int y=0;y<sizeof(area[0]);++y) area[x][y]+=10; //Hide it all in gravel again
		call_out(say,0,"Found solvable game in "+tries+" tries, "+(time()-start)+" seconds.");
		return area;
	}
}

//Thread function: attempt to generate games, passing them back via call_out to generated below.
void generator(array(int) mode)
{
	int tries;
	while (1)
	{
		array(array(int)) area=generate(mode);
		if (area) {call_out(generated,0,mode,area); break;}
		if (!curgame) call_out(say,0,"Still generating... "+(++tries));
	}
}

//Main thread callback when the generator thread succeeds.
void generated(array(int) mode,array(array(int)) area)
{
	if (!equal(gamemode,mode)) return; //Wrong game mode, ignore it. Possibly an old call_out or a race condition.
	if (curgame)
	{
		//Retain this game map for later. TODO: Save to disk.
		nextgame=area; nextmode=mode;
		return;
	}
	//Game generated. Let's do this!
	curgame=area; pitfalls=starttime=gameover=0;
	[int xsz,int ysz,int pits,int ntokens]=mode;
	tb->get_children()->destroy();
	tb->resize(1,1);
	buttons=allocate(xsz,allocate(ysz));
	multiset(int) mines=(<>);
	foreach (area;int x;array(int) col) foreach (col;int y;int cell)
	{
		if (cell==19) mines[x<<8|y]=1;
		GTK2.Button btn=buttons[x][y]=GTK2.Button("   ")->set_focus_on_click(0);
		tb->attach_defaults(btn,x,x+1,y,y+1);
		btn->signal_connect("event",button,sprintf("%c%d",'A'+x,1+y));
	}
	//Place some tokens, in case the user wants to play hideseek. (This
	//could be bracketed with if (playstyle=="hideseek") except that it's
	//currently possible to change playstyle mid-game. It's cheap, anyhow.)
	tokens=({ });
	while (ntokens--) {int cur=random(mines); tokens+=({cur}); mines[cur]=0;}
	sweep("A1");
	tb->show_all();
	mainwindow->resize(1,1);
}

void say(string newmsg)
{
	msg->set_text(newmsg);
}

//See if the game's over. In the case of hideseek games, that means that all tokens have been found.
//Otherwise, it means that all clear squares have been swept, and all pits have been flagged.
//Note that flagging any non-pit will prevent game completion, but sweeping a pit auto-flags it and
//will result in game completion as normal (albeit with a penalty on your score).
void checkdone()
{
	int done=1;
	if (playstyle=="hideseek") {foreach (tokens,int pos) if (pos!=-1) {done=0; break;}}
	else out: foreach (curgame,array(int) col) foreach (col,int cell) if (cell>=10 && cell<29) {done=0; break out;}
	if (done) {say(sprintf("Game completed! %d pit falls, %d seconds.",pitfalls,time()-starttime)); gameover=1;}
}

void showhideseek(int x,int y)
{
	string msg=sprintf("At %c%d",'A'+x,1+y);
	foreach (tokens;int i;int pos)
	{
		if (pos==-1) {msg+=", [found]"; continue;}
		int tx=pos>>8,ty=pos&255;
		if (tx==x && ty==y) {msg+=", [HERE]"; tokens[i]=-1;}
		else msg+=sprintf(", [%.2f]",sqrt((float)(pow(tx-x,2)+pow(ty-y,2))));
	}
	say(msg);
}

void sweep(string sweepme,int|void banner)
{
	if (gameover) return;
	if (!starttime) starttime=time();
	array(array(int)) area=curgame;
	if (sscanf(lower_case(sweepme),"%c%d",int ltr,int num) && ltr>='a' && ltr<='z' && num>0)
	{
		int x=ltr-'a',y=num-1;
		if (x>=sizeof(area) || y>=sizeof(area[0])) {say(sprintf("Out of range (max is %c%d)\n",'A'-1+sizeof(area),sizeof(area[0]))); return;} //Shouldn't happen
		if (area[x][y]==9 && playstyle=="hideseek") showhideseek(x,y); //Re-clicking a pit is valid in hideseek.
		if (area[x][y]<10) return; //Already swept, ignore
		if (banner)
		{
			//Right click - place (toggle, possibly) banner, rather than sweeping
			if (playstyle=="logic" && area[x][y]>9 && area[x][y]<19) {say("That's not a pit!"); gameover=1; return;}
			if (area[x][y]>19)
			{
				area[x][y]-=10;
				buttons[x][y]->set_label(" ");
				return;
			}
			area[x][y]+=10;
			buttons[x][y]->set_label("\u2691"); //U+2691 BLACK FLAG
			checkdone();
			return;
		}
		if (area[x][y]>19) return; //Has a banner - ignore the click
		area[x][y]-=10;
		if (area[x][y]==-1) area[x][y]=9; //If you re-sweep a pit, don't destroy the info.
		if (area[x][y]==9)
		{
			buttons[x][y]->set_label("\u2690"); //U+2690 WHITE FLAG
			++pitfalls;
			if ((<"classic","logic">)[playstyle]) {say("You fell into a pit and broke every bone in your body!"); gameover=1; return;}
			if (playstyle=="hideseek") {showhideseek(x,y); checkdone();}
			else say("You fell into a pit!");
		}
		else buttons[x][y]->set_label(" "+area[x][y]+" ")->set_relief(GTK2.RELIEF_NONE)->set_sensitive(0);
		if (!area[x][y]) //Empty! Sweep the surrounding areas too.
		{
			function trysweep=lambda(int x,int y)
			{
				if (x>=0 && x<sizeof(area) && y>=0 && y<sizeof(area[0]) && area[x][y]>=10 && area[x][y]<=19) sweep(sprintf("%c%d",'A'+x,1+y));
			};
			trysweep(x-1,y);
			trysweep(x-1,y+1);
			trysweep(x,y+1);
			trysweep(x+1,y+1);
			trysweep(x+1,y);
			trysweep(x+1,y-1);
			trysweep(x,y-1);
			trysweep(x-1,y-1);
		}
		checkdone();
	}
}

void button(GTK2.Button self,GTK2.GdkEvent ev,string loc)
{
	//Button click/blip
	if (ev->type!="button_press") return;
	if (ev->button==1) sweep(loc,0);
	if (ev->button==3) sweep(loc,1);
}

void newgame(object self,array|void mode)
{
	//TODO: If current game not finished, prompt.
	if (mode) gamemode=mode;
	curgame=0;
	if (array ng=nextgame) {nextgame=0; generated(nextmode,ng);}
	else say("Generating game, please wait...");
	if (!genthread || genthread->status()!=Thread.THREAD_RUNNING) genthread=Thread.Thread(generator,gamemode);
}

class gameoptions
{
	mapping(string:mixed) win=([]);
	void create()
	{
		object rb=GTK2.RadioButton("Gentle");
		win->mode=({rb,GTK2.RadioButton("Classic",rb),GTK2.RadioButton("Logic",rb),GTK2.RadioButton("Hide/Seek",rb)});
		win->mode[search(({"gentle","classic","logic","hideseek"}),playstyle)]->set_active(1);
		win->mainwindow=GTK2.Window(0)->set_title("Game options")->set_transient_for(mainwindow)->add(GTK2.Vbox(0,0)
			->add(GTK2.Frame("Playing style")->add(GTK2.Vbox(0,0)
				->add(GTK2.Hbox(0,10)->add(win->mode[*])[0])
				->add(GTK2.Label(#"Gentle: The game continues until every square is swept or
	marked. Your score reflects how many pits you hit.
Classic: Sweeping a pit instantly ends the game, but flags
	can be set and removed at will.
Logic: Flagging a non-pit instantly ends the game.
Hide and Seek: Inside some of the pits are tokens. Sweep pits
	to find them; each time you descend into a pit, you
	learn the hypotenusal distances to all tokens. Find
	all the tokens to win.")->set_alignment(0.0,0.0))
			))
			->add(GTK2.HbuttonBox()
				->add(win->pb_close=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_CLOSE])))
			)
		)->show_all();
		win->pb_close->signal_connect("clicked",closewindow);
	}
	void closewindow()
	{
		foreach (win->mode;int i;object rb) if (rb->get_active()) playstyle=({"gentle","classic","logic","hideseek"})[i];
		win->mainwindow->destroy();
	}
}

GTK2.MenuItem menuitem(string label,function event,mixed|void arg)
{
	GTK2.MenuItem mi=GTK2.MenuItem(label);
	mi->signal_connect("activate",event,arg);
	return mi;
}

int main()
{
	GTK2.setup_gtk();
	mainwindow=GTK2.Window(GTK2.WindowToplevel);
	mainwindow->set_title("Pitsweeper")->add(GTK2.Vbox(0,0)
		->pack_start(GTK2.MenuBar()
			->add(GTK2.MenuItem("_Game")->set_submenu(GTK2.Menu()
				->add(menuitem("_New",newgame))
				->add(GTK2.SeparatorMenuItem())
				->add(menuitem("_Easy",newgame,({8,8,8,4})))
				->add(menuitem("_Medium",newgame,({14,14,40,5})))
				->add(menuitem("_Hard",newgame,({20,20,100,10})))
				->add(GTK2.SeparatorMenuItem())
				->add(menuitem("_Options",gameoptions))
			))
		,0,0,0)
		->pack_start(msg=GTK2.Label(""),0,0,0)
		->add(tb=GTK2.Table(1,1,1))
	)->show_all()->signal_connect("delete-event",lambda() {exit(0);});
	newgame(0);
	return -1;
}
