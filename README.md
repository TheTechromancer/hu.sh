# hu.sh
### A privacy script for fresh installs of Linux

<br>

Use the one-liner, if you're feeling adventurous :)
~~~~
bash -c "$(wget -O - https://raw.githubusercontent.com/TheTechromancer/hu.sh/master/hu.sh)"
~~~~

#### Performs the following tasks:

<ul>
	<li>Randomizes all MAC addresses on each boot</li>
	<li>Deletes and disables Bash history (~/.bash_history) for all users (up-arrow in terminal still works)</li>
	<li>Deletes and disables Python history (~/.python_history) for all users</li>
	<li>Deletes and disables Vim history (~/.viminfo) for all users</li>
	<li>Deletes and disables wget hosts history (~/.wget-hsts) for all users</li>
	<li>Deletes all journald logs &amp; disables logging to persistant storage (systemd only)</li>
	<li>Optionally, can Torify the entire system</li>
</ul>

<br>

~~~~
    Usage: hu.sh [options]

      Options:

        -d         Don't Torify
        -o         Only Torify
        -a <port>  Allow incoming port (e.g. 22 for SSH; only applies if Torifying)
        -h         Help
~~~~

## DISCLAIMER: NOT A REPLACEMENT FOR TAILS
## It is your responsibility to check for leaks and verify things are working properly
