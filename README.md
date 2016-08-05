# Thumbs: A simplified integration robot
 ![alt text](https://ryanbrownhill.github.io/github-collab-pres/img/thumbsup.png "Thumbs")
 
## What is this?

When a comment is made on a pull request, a webook will trigger Thumbs to count the thumbs (+1) and merge when it looks good.

## Installation

```
> git clone https://github.com/davidx/thumbs.git
> cd thumbs
> rake install
```
## Setup
```

# ensure user accounts are present
export GITHUB_USER1=bob
export GITHUB_PASS1=apple

export GITHUB_USER=ted
export GITHUB_PASS=pear

export GITHUB_USER2=fred
export GITHUB_PASS2=banana
```
### In a seperate window, start ngrok to collect the forwarding url
```
> ngrok -p 4567
```
### This will display the url to use, for example:
```
Forwarding                    http://699f13d5.ngrok.io -> localhost:4567        
```

### Go to the Github repo Settings->Webhooks & services" and click [Add webhook].
Set the Payload URL to the one you just saved. add /webhook path. 

Example: http://699f13d5.ngrok.io/webhook

Checkbox: Send me Everything

## Test
```
> rake test
```
## Usage

```
> rake start

```


