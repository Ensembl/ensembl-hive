How to connect eHive to Slack
=============================

    With this tutorial, our goal is to explain how to configure eHive
    and Slack to be able to report messages to a Slack channel.

    First of all, you obviously need to have a Slack team. You or
    someone else will have to be allowed to configure Apps.

--------------

1.  Let's first add the "Incoming WebHooks" app to your team

2.  In the main Slack menu select "Apps & Custom Integrations"

3.  Find "Incoming WebHooks" via the search box and select it

4.  You should be on a page that gives an introduction about WebHooks
    and lists the teams you belong too. Somebody may have already
    configured some WebHooks for your team.

    1. If it is the case, click on the "Configure" button next to your
       team name and then "Add Configuration"

    2. Otherwise, click on the "Install" button next to your team name

5.  Let's now configure a webhook to use with eHive

6.  You first need to choose the channel eHive will write too. Although
    the Slack API allows to override the channel and thus use a single
    webhook to post to different channels, we advice to configure 1
    webhook per channel

7.  Click "Add Incoming WebHooks Integration"

8.  The page now shows advanced configuration for the integration. The
    most important here is the "Webhook URL". This is what eHive needs

9.  If you scroll down to "Integration Settings" you can give a
    description for the WebHook, change its name and emoji. Note that
    the latter can be overriden in the Runnable SlackNotification

10. Use the WebHook in eHive

11. Define the ``EHIVE_SLACK_WEBHOOK`` environment variable when running
    your beekeeper

12. Configure the ``slack_webhook`` parameter in the SlackNotification
    Runnable


