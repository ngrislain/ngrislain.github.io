import VersoBlog

open Verso Genre Blog
open Verso Output Html

block_component +directive iframe (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure {{
      <iframe src={{src}}
        style="width: 100%; height: 620px; border: 1px solid #e0e0e0; border-radius: 6px;"
        loading="lazy"
        allowfullscreen="true">
      </iframe>
    }}

block_component +directive hero (alt : String) (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure {{
      <div class="hero-image">
        <img src={{src}} alt={{alt}} />
      </div>
    }}
