# hu.sh
### A privacy script for fresh installs of Linux

<br>

Pipe into bash - if you're feeling adventurous :)
#### bash -c "$(wget -O - https://raw.githubusercontent.com/TheTechromancer/hu.sh/master/hu.sh)"

#### Performs the following tasks:

<ul>
	<li>Deletes and disables bash history for all users</li>
	<li>Deletes and disables python history for all users</li>
	<li>Deletes and disables Vim history (~/.viminfo) for all users</li>
	<li>Deletes all journald logs &amp; disables logging to persistant storage (systemd only)</li>
	<br>
	<li>Coming soon: Tor'ifying the system!

</ul>
