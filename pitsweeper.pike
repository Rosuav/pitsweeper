/* Pitsweeper - Minesweeper variant with guaranteed-solvable games.

TODO: Options dialog with board size (with some presets), death options (does
digging a pit end the game? does marking a non-pit?), etc.
*/

array(array(int)) curgame; //Game field displayed to user
array(array(int)) nextgame; //Game field ready to display
array(array(GTK2.Button)) buttons;
array(int) gamemode=({15,15,60}); //xsize, ysize, pits - what the user asked for
array(int) nextmode; //gamemode of the nextgame

Thread.Thread genthread; //Will always (post-initialization) exist, but might be a terminated thread.

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

array(array(int)) generate(int xsize,int ysize,int pits)
{
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
void generator(int x,int y,int p)
{
	int tries;
	while (1)
	{
		array(array(int)) area=generate(x,y,p);
		if (area) {call_out(generated,0,x,y,p,area); break;}
		if (!curgame) call_out(say,0,"Still generating... "+(++tries));
	}
}

//Main thread callback when the generator thread succeeds.
void generated(int xsz,int ysz,int pits,array(array(int)) area)
{
	if (!equal(gamemode,({xsz,ysz,pits}))) return; //Wrong game mode, ignore it. Possibly an old call_out or a race condition.
	if (curgame)
	{
		//Retain this game map for later. TODO: Save to disk.
		nextgame=area; nextmode=({xsz,ysz,pits});
		return;
	}
	//Game generated. Let's do this!
	curgame=area;
	tb->resize(1,1);
	tb->get_children()->destroy();
	buttons=allocate(xsz,allocate(ysz));
	foreach (area;int x;array(int) col) foreach (col;int y;int cell)
	{
		GTK2.Button btn=buttons[x][y]=GTK2.Button("   ")->set_focus_on_click(0);
		tb->attach_defaults(btn,y,y+1,x,x+1);
		btn->signal_connect("event",button,sprintf("%c%d",'A'+x,1+y));
	}
	sweep("A1");
	tb->show_all();
}

array sweepmsg=({
	"The bristles do not bend at all.",
	"Very few bristles bend.",
	"A few bristles bend.",
	"Some bristles bend.",
	"Half the bristles bend!",
	"More than half the bristles bend!",
	"Three-quarters of the bristles bend!",
	"Nearly all the bristles bend!",
	"EVERY BRISTLE on the broom bends!!",
	"There is a pit there!" //9 = you just swept yourself into a pit. Also used for -1.
});

/* Maybe reinstate the hidden-tokens mechanic? Code straight from Minstrel Hall and won't work here unadjusted.
		if (nhiddens)
		{
			multiset(int) mines=(<>);
			foreach (area;int x;array(int) row) foreach (row;int y;int cell) if (cell==19) mines[x<<8|y]=1;
			array(int) hiddens=({ });
			while (nhiddens--) {int cur=random(mines); hiddens+=({cur}); mines[cur]=0;}
			caller->location->tmp->pitsweeper_hiddens=hiddens;
		}
*/

void say(string newmsg)
{
	msg->set_text(newmsg);
}

void sweep(string sweepme,int|void banner)
{
	array(array(int)) area=curgame;
	if (sscanf(lower_case(sweepme),"%c%d",int ltr,int num) && ltr>='a' && ltr<='z' && num>0)
	{
		int x=ltr-'a',y=num-1;
		if (x>=sizeof(area) || y>=sizeof(area[0])) {say(sprintf("Out of range (max is %c%d)\n",'A'-1+sizeof(area),sizeof(area[0]))); return;} //Shouldn't happen
		if (area[x][y]<10) return; //Already swept, ignore
		string msg=sprintf("%c%d",'A'+x,1+y);
		if (banner)
		{
			//Right click - place (toggle, possibly) banner, rather than sweeping
			if (area[x][y]>19)
			{
				area[x][y]-=10;
				buttons[x][y]->set_label(" ");
				return;
			}
			area[x][y]+=10;
			buttons[x][y]->set_label("\u2691");
			return;
		}
		if (area[x][y]>19) return; //Has a banner - ignore the click
		area[x][y]-=10;
		if (area[x][y]==-1) area[x][y]=9; //If you re-sweep a pit, don't destroy the info.
		if (area[x][y]==9)
		{
			buttons[x][y]->set_label("\u2691")->set_sensitive(0);
			say("You fell into a pit!");
			//May be game over (or may just impact your score).
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
		/* More hidden-tokens code.
		if (area[x][y]==9) //Pit. Check for hideseek tokens.
		{
			prime->cmds->roll(caller,"(falling damage) 4d6");
			if (array(int) hiddens=caller->location->tmp->pitsweeper_hiddens)
			{
				string msg="";
				foreach (hiddens,int pos)
				{
					int hx=pos>>8,hy=pos&255;
					if (hx==x && hy==y)
					{
						emote("%n found a hidden token! WOOHOO!",caller,"You found a hidden token! CONGRATS!");
						if (!sizeof(caller->location->tmp->pitsweeper_hiddens-=({pos}))) {m_delete(caller->location->tmp,"pitsweeper_hiddens"); caller->tell("And that's all the tokens found!\n");}
						continue;
					}
					float dist=sqrt((float)(pow(hx-x,2)+pow(hy-y,2)));
					msg+=sprintf("There is a token %.4f feet (%.4f squares) from this pit.\n",dist*5,dist);
				}
				if (msg!="") bcast(caller->location,msg);
			}
		}
		*/
	}
}

void button(GTK2.Button self,GTK2.GdkEvent ev,string loc)
{
	//Button click/blip
	if (ev->type!="button_press") return;
	if (ev->button==1) sweep(loc,0);
	if (ev->button==3) sweep(loc,1);
}

void newgame()
{
	//TODO: If current game not finished, prompt.
	curgame=0;
	if (array ng=nextgame) {nextgame=0; generated(@nextmode,ng);}
	else say("Generating game, please wait...");
	if (!genthread || genthread->status()!=Thread.THREAD_RUNNING) genthread=Thread.Thread(generator,@gamemode);
}

GTK2.MenuItem menuitem(string label,function event)
{
	GTK2.MenuItem mi=GTK2.MenuItem(label);
	mi->signal_connect("activate",event);
	return mi;
}

int main()
{
	GTK2.setup_gtk();
	GTK2.Window(GTK2.WindowToplevel)->set_title("Pitsweeper")->add(GTK2.Vbox(0,0)
		->pack_start(GTK2.MenuBar()
			->add(GTK2.MenuItem("_Game")->set_submenu((object)GTK2.Menu()
				->add(menuitem("_New",newgame))
			))
		,0,0,0)
		->pack_start(msg=GTK2.Label(""),0,0,0)
		->add(tb=GTK2.Table(1,1,1))
	)->show_all()->signal_connect("delete-event",lambda() {exit(0);});
	newgame();
	return -1;
}
