---
layout: default
title: Tags
permalink: /tags/
---
{% for tag in site.tags %}
  - [{{tag | first}}]({{site.url}}{{site.baseurl}}{{page.url}}{{tag | first}})
{% endfor %}
