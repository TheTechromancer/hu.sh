# hu.sh
### A privacy script for fresh installs of Linux

<br>

Use the one-liner, if you're feeling adventurous :)
#### bash -c "$(wget -O - https://raw.githubusercontent.com/TheTechromancer/hu.sh/master/hu.sh)"

#### Performs the following tasks:

<ul>
	<li>Deletes and disables bash history for all users</li>
	<li>Deletes and disables python history for all users</li>
	<li>Deletes and disables Vim history (~/.viminfo) for all users</li>
	<li>Deletes all journald logs &amp; disables logging to persistant storage (systemd only)</li>
	<li>Tor'ifies the system</li>

</ul>

### usage: hu.sh [option]<br>

  Options:<br>

     -d   Don't torify<br>
     -o   Only torify<br>
     -h   Help