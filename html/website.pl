#!/usr/bin/env perl -w

use strict;
use warnings;
use utf8;

use DateTime;

use Cwd qw(getcwd);
use Mojolicious::Lite;
use Mojo::UserAgent;
use Data::Dumper;

plugin 'RenderFile';

get '/' => sub {
   my ($self) = @_;
   $self->stash("no_side_bar", 0);
   $self->render("index", root => 1, cat => "", no_disqus => 1);
};

# special code to handle ,,rexify --search'' requests
get '/get/recipes' => sub {
   my ($self) = @_;
   my $ua = Mojo::UserAgent->new;
   $self->render_text($ua->get("https://raw.github.com/krimdomu/rex-recipes/master/recipes.yml")->res->body);
};

# special code to handle ,,rexify --use'' requests
get '/get/mod/*mod' => sub {
   my ($self) = @_;

   my $cur_dir = getcwd;

   my $mod = $self->param("mod");
   my $mod_name = $mod . ".pm";

   if( ! -d "/tmp/scratch") {
      mkdir "/tmp/scratch";
   }

   chdir("/tmp/scratch");

   my $u = get_random(32, 'a' .. 'z');  
   system("git clone git://github.com/krimdomu/rex-recipes.git $u >/dev/null 2>&1");
   chdir("$u");
   system("git checkout master");

   system("tar czf ../$u.tar.gz $mod $mod_name >/dev/null 2>&1");

   chdir($cur_dir);

   $self->render_file(filepath => "/tmp/scratch/$u.tar.gz");
};

get '/search' => sub {
   my ($self) = @_;

   my $term = $self->param("q");

   $term =~ s/(\w+)/$1*/g;

   my $ua = Mojo::UserAgent->new;
   my $tx = $ua->post("http://localhost:9200/_search?pretty=true", json => {
      query => {
         query_string => {
            query => $term,
         },
      },
      fields => [qw/fs title/],
      highlight => {
         fields => {
            file => {},
         },
      },
   });

   $self->stash("no_side_bar", 0);
   $self->stash("root", 0);
   $self->stash("no_disqus", 1);
   $self->stash("cat", "");


   if(my $json = $tx->res->json) {
      return $self->render("search", hits => $json->{hits});
   }
   else {
      return $self->render("search", hits => { total => 0, });
   }
};


get '/*file' => sub {
   my ($self) = @_;

   my $template = $self->param("file");

   my ($cat) = ($template =~ m/^([^\/]+)\//);
   $cat ||= "";
   $self->stash("cat", $cat);

   if($template eq "howtos/compatibility.html") {
      $self->stash("no_side_bar", 1);
   }
   else {
      $self->stash("no_side_bar", 0);
   }

   if(-f "public/$template") {
      return $self->render_file(filepath => "public/$template", no_disqus => 0, root => 0);
   }

   if(-d "templates/$template") {
      return $self->redirect_to("$template/index.html", root => 0);
   }

   if(-f "templates/$template.ep") {
      $template =~ s/\.html$//;
      $self->render($template, no_disqus => 0, root => 0);
   }
   else {
      $self->render('404', status => 404, no_disqus => 1, root => 0);
   }

};


app->start;

__DATA__

@@ search.html.ep

% layout 'default';
% title 'Search for ' . param('q');

% if( $hits->{total} == 0 ) {

<p>I'm sorry. Your query had no results!</p>

% } else {

% my @api_results     = grep { $_->{_index} eq "api" } @{ $hits->{hits} };
% my @webpage_results = grep { $_->{_index} eq "webpage" } @{ $hits->{hits} };

% if(@api_results) {
<h1>API</h1>
   <ul>
   % for my $r (@api_results) {
      <li>
         <p><a href="<%= $r->{fields}->{fs} %>"><%= $r->{fields}->{title} %></a></p>
         <div class="small-vspace"></div>
         <p><b>Found here:</b></p>
         % for my $h (@{ $r->{highlight}->{file} }) {
         <p class="highlight-search" style="margin-left: 0px"><%== $h %></p>
         % }
         <div class="small-vspace"></div>
      </li>
   % }
   </ul>
% }

% if(@webpage_results) {
<div class="vspace"></div>
<h1>Website</h1>
   <ul>
   % for my $r (@webpage_results) {
      <li>
         <a href="<%= $r->{fields}->{fs} %>"><%= $r->{fields}->{title} %></a>
         <div class="small-vspace"></div>
         <p><b>Found here:</b></p>
         % for my $h (@{ $r->{highlight}->{file} }) {
         <p class="highlight-search" style="margin-left: 0px"><%== $h %></p>
         % }
         <div class="small-vspace"></div>
      </li>
   % }
   </ul>
% }

% }

@@ 404.html.ep

% layout 'default';
% title '404 - File not found';

<h1>404 - I'm really sorry :(</h1>
<p>Hello. I'm a Webserver. And i'm there to serve files for you. But i'm really sorry :( I can't find the file you want to see.</p>

@@ index_head.html.ep

         <div id="head-div">
            <div class="head_container">
               <div class="slogan">
                  <h1>Automate Everything, Relax Anytime</h1>
                  <div class="slogan_list">
                     <ul>
                        <li>&gt; Integrates seamless in your running environment</li>
                        <li>&gt; Easy to use and extend</li>
                        <li>&gt; Easy to learn, it's just plain Perl</li>
                        <li>&gt; Apache 2.0 licensed</li>
                     </ul>
                  </div> <!-- slogan_list -->

                  <div class="source">
                     <pre><code class="perl">task prepare => sub {
   install "apache2";
   service apache2 => ensure => "started";
};</code></pre>
                  </div> <!-- source -->
                  <a class="headlink" href="/howtos/start.html">Read the Getting Started Guide</a>
               </div> <!-- slogan -->

            </div> <!-- head_container -->
         </div>



@@ navigation.html.ep

             <div class="nav_links">
               <ul>
                  <li <% if($cat eq "") { %>class="active" <% } %>><a href="/">Home</a></li>
                  <li <% if($cat eq "get") { %>class="active" <% } %>><a href="/get" title="Install Rex on your systems">Get Rex</a></li>
                  <li <% if($cat eq "contribute") { %>class="active" <% } %>><a href="/contribute" title="Help Rex to get even better">Contribute</a></li>
                  <li <% if($cat eq "support") { %>class="active" <% } %>><a href="/support" title="Commercial Support">Support</a></li>
                  <li <% if($cat eq "howtos" || $cat eq "modules") { %>class="active" <% } %>>
                     <b class="arrow_box"></b>
                     <a href="#" title="Examples, Howtos and Documentation" class="dropdown_link">Docs</a>
                     <ul class="dropdown_menu dropdown_docs">
                        <li><a href="/howtos/index.html#guides">Guides</a></li>
                        <li><a href="/howtos/index.html#howtos">Howtos</a></li>
                        <li><a href="/howtos/index.html#snippets">Snippets</a></li>
                        <li>
                           <a href="/howtos/book.html">Rex Book (work in progress)</a>
                        </li>
                        <li class="divider"></li>
                        <li><a href="/api/index.html">API</a></li>
                        <li class="divider"></li>
                        <li><a href="http://rex.perl-china.com/">Chinese Rex Community Website</a></li>
                     </ul>
                  </li>
               </ul>
            </div>

@@ layouts/default.html.ep
<!DOCTYPE html 
     PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
   <head>
      <meta http-equiv="content-type" content="text/html; charset=utf-8" />
   
      <title><%= title %></title>

      <meta name="viewport" content="width=1024, initial-scale=0.5">

      <link href="http://yandex.st/highlightjs/7.3/styles/magula.min.css" rel="stylesheet"/>
      <link rel="stylesheet" href="/css/bootstrap.min.css?20130325" type="text/css" media="screen" charset="utf-8" />
      <link rel="stylesheet" href="/css/default.css?20131013" type="text/css" media="screen" charset="utf-8" />

      <meta name="description" content="(R)?ex - manage all your boxes from a central point - Datacenter Automation and Configuration Management" />
      <meta name="keywords" content="Systemadministration, Datacenter, Automation, Rex, Rexfiy, Rexfile, Example, Remote, Configuration, Management, Framework, SSH, Linux" />

      <style>
      % if($no_side_bar) {
         #content_container {
            margin-left: 5px;
         }

         #widgets {
            display: none;
         }
      % }
      </style>

   </head>
   <body>

      <div id="page">

      % if($root) {
         <div id="index-top-div" class="top_div">
            <h1>(R)?ex <small>Deployment &amp; Configuration Management</small></h1>
         </div>

         %= include 'index_head';
         <div class="nav_title">
            <span style="color: #7b4d29;">Y</span>our <span style="color: #7b4d29;">W</span>ay
         </div>

         <div id="index-nav-div">
            %= include 'navigation';
         </div>
      % } else {
         <div id="top-div" class="top_div">
            <h1>(R)?ex <small>Deployment &amp; Configuration Management</small></h1>
            <div id="nav-div">
               %= include 'navigation';
            </div>
         </div>
      % }

         <div id="widgets_container">
            <div id="widgets">
               <h2>Search</h2>
               <form action="/search" method="GET">
                  <input type="text" name="q" id="q" class="search_field" /><button class="btn">Go</button>
               </form>
               <h2>News</h2>

               <div class="news_widget">
                  <div class="news_date">2013-09-21</div>
                  <div class="news_content">The talk of <a href="http://www.kieler-linuxtag.de/">Kieler Linux Tage</a> is uploaded to <a href="http://de.slideshare.net/jfried/rex-infrastruktur-als-code">slideshare</a> and on <a href="http://www.youtube.com/watch?v=398v_AS7mMk">youtube</a> (language: german).</div>
               </div>

               <div class="news_widget">
                  <div class="news_date">2013-09-16</div>
                  <div class="news_content">(R)?ex 0.43.0 released. This release adds the option to cache the machine inventory so that the execution will be faster, and the ability to create a report of the changes Rex did during the run. It also adds limited support for OpenWrt. For a complete list of changes see the <a href="https://github.com/krimdomu/Rex/wiki/New0.43">Changelog</a> on Github.</div>
               </div>


               <div class="news_widget">
                  <div class="news_date">2013-08-12</div>
                  <div class="news_content">The lightning talk of <a href="http://yapceurope.org/">yapc.eu</a> is uploaded to <a href="http://de.slideshare.net/jfried/rex-25172864">slideshare</a>.</div>
               </div>


               <div class="news_widget">
                  <div class="news_date">2013-05-23</div>
                  <div class="news_content">Inovex <a href="http://www.inovex.de/news-events/news/">just announced</a> that they offer professional support for Rex.</div>
               </div>



               <div class="news_widget">
                  <div class="news_date">2013-03-20</div>
                  <div class="news_content">
                     <img src="/img/init_mittelstand.png" style="float: left; height: 70px;" />
                     <p>We are proud to announce that Rex was voted under the Best Open Source solutions 2013 by <a href="http://www.imittelstand.de/">initiative mittelstand</a>. And we want to thank <a href="http://inovex.de">inovex</a> for the support to make this happen.</p>
                  </div>
               </div>

               <h2>Conferences</h2>
               <p>29. November: <a href="http://sfd.org.hu/instant-devops">Instant DevOps</a> talk at <a href="http://sfd.org.hu">Free Software Conference of Szeged</a> featuring (R)?ex</p>
               <p>09. November - 10. November 2013 talk and booth at <a href="http://www.openrheinruhr.de/">Open Rhein Ruhr</a>.</p>

               <h2>Need Help?</h2>
               <p>Rex is a pure Open Source project. So you can find community support in the following places.</p>
               <ul>
                  <li>IRC: #rex on freenode</li>
                  <li>Groups: <a href="https://groups.google.com/group/rex-users/">rex-users</a></li>
                  <li>Issues: <a href="https://github.com/Krimdomu/Rex/issues">on Github</a></li>
                  <li>Feature: You miss a <a href="/feature.html">feature</a>?</li>
                  <li>Professional Support: <a href="http://www.inovex.de/news-events/news/">by inovex</a></li>
               </ul>
            </div>
         </div> <!-- widgets -->

         <div id="content_container">
            <div id="content">
               <%= content %>

 % if( ! $no_disqus) {

    <div id="disqus_thread" style="margin-top: 45px;"></div>
    <script type="text/javascript">
        /* * * CONFIGURATION VARIABLES: EDIT BEFORE PASTING INTO YOUR WEBPAGE * * */
        var disqus_shortname = 'rexify'; // required: replace example with your forum shortname

        /* * * DON'T EDIT BELOW THIS LINE * * */
        (function() {
            var dsq = document.createElement('script'); dsq.type = 'text/javascript'; dsq.async = true;
            dsq.src = 'http://' + disqus_shortname + '.disqus.com/embed.js';
            (document.getElementsByTagName('head')[0] || document.getElementsByTagName('body')[0]).appendChild(dsq);
        })();
    </script>
    <noscript>Please enable JavaScript to view the <a href="http://disqus.com/?ref_noscript">comments powered by Disqus.</a></noscript>
    <a href="http://disqus.com" class="dsq-brlink">comments powered by <span class="logo-disqus">Disqus</span></a>
    
    % }

            </div>
         </div> <!-- content -->

      </div> <!-- page -->
      

     <a href="http://github.com/Krimdomu/Rex"><img style="position: absolute; top: 0; right: 0; border: 0;" src="https://s3.amazonaws.com/github/ribbons/forkme_right_orange_ff7600.png" alt="Fork me on GitHub" /></a>

   <div class="clearfix"></div>
   <div class="bottom_bar">
      <a href="https://groups.google.com/group/rex-users/">Google Group</a> / <a href="http://twitter.com/jfried83">Twitter</a> / <a href="https://github.com/krimdomu/Rex">Github</a> / <a href="http://www.freelists.org/list/rex-users">Mailinglist</a> / <a href="irc://irc.freenode.net/rex">irc.freenode.net #rex</a><span style="display: none;" id="syntax_high"> / <a href="#" id="link_syntax_high">Enable Syntax Highlighting</a></span>&nbsp;&nbsp;&nbsp;-.ô.-&nbsp;&nbsp;&nbsp;<a href="http://www.disclaimer.de/disclaimer.htm" target="_blank">Disclaimer</a></p>
   </div>

   <script type="text/javascript" charset="utf-8" src="/js/jquery.js"></script>
   <script type="text/javascript" charset="utf-8" src="/js/bootstrap.min.js"></script>
   <script type="text/javascript" charset="utf-8" src="/js/menu.js"></script>

   <script>
      if($(window).width() <= 1100) {
         // hide API link
         $("#li_api").hide();
      }
      $(window).on('resize', function() {
       if($(window).width() <= 1100) {
         // hide API link
         $("#li_api").hide();
       }
       else {
         $("#li_api").show();
       }
     
      });
   </script>


<!-- Piwik -->
<script type="text/javascript"> 
  var _paq = _paq || [];
  _paq.push(['trackPageView']);
  _paq.push(['enableLinkTracking']);
  (function() {
    var u=(("https:" == document.location.protocol) ? "https" : "http") + "://www.rexify.org/stats/";
    _paq.push(['setTrackerUrl', u+'piwik.php']);
    _paq.push(['setSiteId', 1]);
    var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0]; g.type='text/javascript';
    g.defer=true; g.async=true; g.src=u+'piwik.js'; s.parentNode.insertBefore(g,s);
  })();

</script>
<noscript><p><img src="http://www.rexify.org/stats/piwik.php?idsite=1" style="border:0" alt="" /></p></noscript>
<!-- End Piwik Code -->


<script src="http://yandex.st/highlightjs/7.3/highlight.min.js"></script>
<script src="/js/browser.js"></script>
<script>
  if(BrowserDetect.browser == "Firefox" && BrowserDetect.OS == "Linux") {
     window.setTimeout(function() {
        $("#syntax_high").show();
        $("#link_syntax_high").click(function(event) {
           event.preventDefault();
           hljs.tabReplace = '    ';
           hljs.initHighlighting();
        });
     }, 1500);
  }
  else {
     window.setTimeout(function() {
        hljs.tabReplace = '    ';
        hljs.initHighlighting();
        //$("#q").focus();
     }, 1000);
  }
</script>


   </body>

</html>

