/* Pitsweeper - Minesweeper variant with guaranteed-solvable games.

TODO: Options dialog with board size (with some presets), death options (does
digging a pit end the game? does marking a non-pit?), etc.
*/

array(array(int)) curgame; //Game field displayed to user

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

region hint(array(array(int)) area,int cutoff)
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
		if (time()>=cutoff) return 0;
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

array(array(int)) generate(int xsize,int ysize,int pits,int|void timeout)
{
	int cutoff=time()+(timeout||3);
	int tries=0;
	while (time()<cutoff)
	{
		++tries;
		array(array(int)) area=allocate(xsize,allocate(ysize));
		//Dig some pits.
		for (int i=0;i<pits;++i)
		{
			if (time()>=cutoff) return 0;
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
		while (region r=hint(area,cutoff)) foreach (indices(r->unk),int xy) if (area[xy>>8][xy&255]>9) area[xy>>8][xy&255]-=10;
		int done=1;
		foreach (area,array(int) col) foreach (col,int cell) if (cell>9) {done=0; break;}
		if (!done) continue;
		for (int x=0;x<sizeof(area);++x) for (int y=0;y<sizeof(area[0]);++y) area[x][y]+=10; //Hide it all in gravel again
		return area;
	}
	return 0;
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

void say(string msg)
{
	//some_label->set_text(msg);
}

void sweep(string sweepme,int|void banner)
{
	array(array(int)) area=curgame;
	if (sscanf(sweepme,"%c%d",int ltr,int num) && ltr>='a' && ltr<='z' && num>0)
	{
		int x=ltr-'a',y=num-1;
		if (x>=sizeof(area) || y>=sizeof(area[0])) {say(sprintf("Out of range (max is %c%d)\n",'A'-1+sizeof(area),sizeof(area[0]))); return;}
		if (area[x][y]<9) return; //Already swept, ignore
		string msg=sprintf("%c%d",'A'+x,1+y);
		/* Rather than having the 'confirm' option, probably better to simply allow removal of banners (assuming misplaced banner doesn't equal end of game).
		if (!confirm && (area[x][y]==9 || area[x][y]>19))
		{
			if (banner) caller->tell("That place already has a pit banner on it.\n");
			else caller->tell("That place has a pit banner on it. Use 'sweep confirm "+msg+"' to ignore it.\n");
			continue;
		}
		if (area[x][y]>19) {area[x][y]-=10; msg+=", ignoring the banner";} //So if you "banner confirm B4" when there's already a banner there, it'll say "You place a banner on B4, ignoring the banner.". Weird but it won't break anything.
		*/
		if (banner)
		{
			//The command was "banner <loc>" not "sweep <loc>".
			area[x][y]+=10;
			say("You place a banner on "+msg+".");
			return;
		}
		say("You sweep "+msg+". "+sweepmsg[area[x][y]-=10]);
		if (area[x][y]==-1) area[x][y]=9; //If you re-sweep a pit, don't destroy the info.
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

int main()
{
	GTK2.setup_gtk();
	GTK2.Window(GTK2.WindowToplevel)->set_title("Pitsweeper")
		->add(GTK2.Label("This is a stub. There's currently no functionality here, sorry!"))
		->show_all()->signal_connect("delete-event",lambda() {exit(0);});
	return -1;
}
