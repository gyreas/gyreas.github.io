serve:
    bundler exec jekyll serve
dev:
    bundler exec jekyll serve --watch --drafts --incremental --livereload

clean:
    jekyll clean
