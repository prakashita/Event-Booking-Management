# Scribbr Citation Generator Source-Type Field Inventory

Checked: 2026-05-03

Entry point inspected: https://www.scribbr.com/citation/generator/cite/

Important note: the current Scribbr source-type list shows 36 source types. I did not see a separate "Newsletter" source type in the current list. For newsletter-like content, the closest visible types are usually `Blog post`, `Online magazine article`, `Webpage`, or `Press release`, depending on the source.

## How to read this

- `Source type` is always the first required selector.
- `Title` means the title of the cited item: page title, article title, book title, episode title, etc.
- `Content` replaces title for short-form content such as comments and social posts.
- `Container title` is the larger thing containing the item. Depending on source type, this displays conceptually as website name, journal name, book title, blog name, newspaper/magazine name, dictionary/encyclopedia title, forum/platform name, dataset repository, etc.
- `Contributors` supports adding a person or an organization.
- Dates are split by use: `Issued` is publication/release date, `Accessed` is retrieval date, `Composed` is creation date for artwork, and `Submitted` is submission/completion date for theses.
- Date controls use a year input plus month/day selectors where applicable. Some forms also show an original publication date toggle.
- `Place` fields are `Country`, `Region`, and `Locality`.
- `URL`, `DOI`, and `PDF URL` are separate fields where applicable.

## Common Controls

| Field key | Meaning in the UI |
| --- | --- |
| Source type | The selected source type, e.g. Webpage, Journal article, Book |
| Title | Main title of the cited item |
| Content | Comment or post text |
| Container title | Parent source name: website, journal, book, blog, newspaper, magazine, platform, dictionary, encyclopedia, collection, etc. |
| Collection title | Series title, used for podcast and TV episodes |
| Contributors | Authors, creators, editors, inventors, hosts, directors, organizations, etc.; form offers add person and add organization |
| Issued | Publication/release date |
| Accessed | Retrieval/access date, with a set-to-today control |
| Composed | Artwork creation/composition date |
| Submitted | Thesis/dissertation submission date |
| Publisher | Publisher, producer, institution, organization, or production company |
| Source | Database/source/channel/platform field, depending on source type |
| URL | Web address |
| DOI | Digital Object Identifier |
| PDF URL | Direct PDF URL |
| Note | Optional extra note, hidden behind an add-note control |

## Source Types

### 1. Artwork

Source URL: https://www.scribbr.com/citation/generator/cite/artwork/

Required:
- Source type: Artwork
- Title

Recommended:
- Contributors
- Composed date

Other fields:
- Medium
- Archive / museum / collection
- Place: country, region, locality
- Note

### 2. Blog Post

Source URL: https://www.scribbr.com/citation/generator/cite/blog-post/

Required:
- Source type: Blog post
- Title
- Container title, typically blog name

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Accessed date
- Note

### 3. Book

Source URL: https://www.scribbr.com/citation/generator/cite/book/

Required:
- Source type: Book
- Title

Recommended:
- Contributors
- Medium
- Issued date
- Publisher

Other fields:
- Edition
- Volume, with range support
- Original publication date toggle
- Publisher place
- DOI
- PDF URL
- URL
- Note

### 4. Book Chapter

Source URL: https://www.scribbr.com/citation/generator/cite/book-chapter/

Required:
- Source type: Book chapter
- Title
- Container title, typically book title

Recommended:
- Contributors
- Page / page range

Other fields:
- Edition
- Volume, with range support
- Medium
- Issued date
- Original publication date toggle
- Publisher
- Publisher place
- DOI
- PDF URL
- URL
- Note

### 5. Comment

Source URL: https://www.scribbr.com/citation/generator/cite/comment/

Required:
- Source type: Comment
- Content

Recommended:
- Container title, typically page/post/video/article title
- Contributors
- Issued date
- Source
- URL

Other fields:
- Accessed date
- Note

### 6. Conference Proceeding

Source URL: https://www.scribbr.com/citation/generator/cite/conference-proceeding/

Required:
- Source type: Conference proceeding
- Title

Recommended:
- Contributors
- Issued date

Other fields:
- Container title, typically proceedings/book/journal title
- Edition
- Volume, with range support
- Medium
- Publisher
- Publisher place
- DOI
- PDF URL
- URL
- Note

### 7. Conference Session

Source URL: https://www.scribbr.com/citation/generator/cite/conference-session/

Required:
- Source type: Conference session
- Title

Recommended:
- Contributors
- Medium
- Event
- URL

Other fields:
- Container title
- Event name
- Place: country, region, locality
- Note

### 8. Dataset

Source URL: https://www.scribbr.com/citation/generator/cite/data-set/

Required:
- Source type: Dataset
- Title

Recommended:
- Contributors
- URL

Other fields:
- Container title, typically repository/database/project
- Version
- Medium
- Status, with published and unpublished options
- Issued date
- Publisher
- DOI
- PDF URL
- Note

### 9. Film

Source URL: https://www.scribbr.com/citation/generator/cite/film/

Required:
- Source type: Film
- Title

Recommended:
- Contributors
- Issued date
- Publisher

Other fields:
- Version
- Medium
- URL
- Note

### 10. Forum Post

Source URL: https://www.scribbr.com/citation/generator/cite/forum-post/

Required:
- Source type: Forum post
- Title

Recommended:
- Container title, typically forum/subforum/platform name
- Contributors
- Issued date
- URL

Other fields:
- Accessed date
- Note

### 11. Image

Source URL: https://www.scribbr.com/citation/generator/cite/image/

Required:
- Source type: Image
- Title

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Container title, typically site/publication/museum/source name
- Note

### 12. Journal Article

Source URL: https://www.scribbr.com/citation/generator/cite/journal-article/

Required:
- Source type: Journal article
- Title
- Container title, typically journal name

Recommended:
- Contributors
- Status
- Issued date
- Page / page range
- DOI

Other fields:
- Volume, with range support
- Issue
- Number / article number
- Status options: published, in press
- Source
- PDF URL
- URL
- Note

### 13. Online Dictionary Entry

Source URL: https://www.scribbr.com/citation/generator/cite/online-dictionary-entry/

Required:
- Source type: Online dictionary entry
- Title

Recommended:
- Issued date
- URL

Other fields:
- Container title, typically dictionary name
- Contributors
- Accessed date
- Note

### 14. Online Encyclopedia Entry

Source URL: https://www.scribbr.com/citation/generator/cite/online-encyclopedia-entry/

Required:
- Source type: Online encyclopedia entry
- Title

Recommended:
- Issued date
- URL

Other fields:
- Container title, typically encyclopedia name
- Contributors
- Accessed date
- Note

### 15. Online Magazine Article

Source URL: https://www.scribbr.com/citation/generator/cite/online-magazine-article/

Required:
- Source type: Online magazine article
- Title
- Container title, typically magazine name

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Original publication date toggle
- Accessed date
- Publisher
- Note

### 16. Online Newspaper Article

Source URL: https://www.scribbr.com/citation/generator/cite/online-news-article/

Required:
- Source type: Online newspaper article
- Title
- Container title, typically newspaper name

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Publisher
- Note

### 17. Patent

Source URL: https://www.scribbr.com/citation/generator/cite/patent/

Required:
- Source type: Patent
- Title
- Contributors, typically inventor/applicant
- Number
- Jurisdiction
- Authority
- Issued date

Other fields:
- Container title
- URL
- Note

### 18. Podcast

Source URL: https://www.scribbr.com/citation/generator/cite/podcast/

Required:
- Source type: Podcast
- Title

Recommended:
- Contributors
- URL

Other fields:
- Publisher
- Source
- Note

### 19. Podcast Episode

Source URL: https://www.scribbr.com/citation/generator/cite/podcast-episode/

Required:
- Source type: Podcast episode
- Collection title, typically podcast name

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Title, typically episode title
- Season
- Episode
- Accessed date
- Publisher
- Source
- Note

### 20. Presentation Slides

Source URL: https://www.scribbr.com/citation/generator/cite/presentation-slides/

Required:
- Source type: Presentation slides
- Title

Recommended:
- Contributors
- Medium
- Issued date
- Event
- URL

Other fields:
- Container title
- Original publication date toggle
- Event name
- Place: country, region, locality
- Page / page range
- Note

### 21. Press Release

Source URL: https://www.scribbr.com/citation/generator/cite/press-release/

Required:
- Source type: Press release
- Title

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Accessed date
- Note

### 22. Print Dictionary Entry

Source URL: https://www.scribbr.com/citation/generator/cite/print-dictionary-entry/

Required:
- Source type: Print dictionary entry
- Title
- Container title, typically dictionary name

Recommended:
- Contributors
- Issued date
- Publisher

Other fields:
- Edition
- Volume, with range support
- Number
- Original publication date toggle
- Publisher place
- Page / page range
- Note

### 23. Print Encyclopedia Entry

Source URL: https://www.scribbr.com/citation/generator/cite/print-encyclopedia-entry/

Required:
- Source type: Print encyclopedia entry
- Title
- Container title, typically encyclopedia name

Recommended:
- Contributors
- Issued date
- Publisher

Other fields:
- Edition
- Volume, with range support
- Original publication date toggle
- Publisher place
- Note

### 24. Print Magazine Article

Source URL: https://www.scribbr.com/citation/generator/cite/print-magazine-article/

Required:
- Source type: Print magazine article
- Title
- Container title, typically magazine name

Recommended:
- Contributors
- Issued date
- Page / page range

Other fields:
- Issue
- Original publication date toggle
- Source
- Note

### 25. Print Newspaper Article

Source URL: https://www.scribbr.com/citation/generator/cite/newspaper-article/

Required:
- Source type: Print newspaper article
- Title
- Container title, typically newspaper name

Recommended:
- Contributors
- Issued date
- Page / page range

Other fields:
- Edition
- Section
- Original publication date toggle
- Publisher
- Publisher place
- Note

### 26. Report

Source URL: https://www.scribbr.com/citation/generator/cite/report/

Required:
- Source type: Report
- Title

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Container title, often report series/collection
- Number
- Accessed date
- Publisher
- Publisher place
- DOI
- PDF URL
- Note

### 27. Social Media Post

Source URL: https://www.scribbr.com/citation/generator/cite/social-media-post/

Required:
- Source type: Social media post
- Content

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Container title, typically platform/profile/context
- Accessed date
- Note

### 28. Software

Source URL: https://www.scribbr.com/citation/generator/cite/software/

Required:
- Source type: Software
- Title

Recommended:
- Contributors
- Version
- Issued date

Other fields:
- Container title
- Publisher
- URL
- Note

### 29. Speech

Source URL: https://www.scribbr.com/citation/generator/cite/speech/

Required:
- Source type: Speech
- Title

Recommended:
- Contributors
- Event
- URL

Other fields:
- Container title
- Issued date
- Event name
- Place: country, region, locality
- Note

### 30. Thesis

Source URL: https://www.scribbr.com/citation/generator/cite/thesis/

Required:
- Source type: Thesis
- Title

Recommended:
- Contributors
- Genre
- Submitted date
- Publisher

Other fields:
- DOI
- PDF URL
- Note

### 31. TV Show

Source URL: https://www.scribbr.com/citation/generator/cite/tv-show/

Required:
- Source type: TV show
- Title

Recommended:
- Contributors
- Issued date
- Publisher

Other fields:
- Medium
- Source
- URL
- Note

### 32. TV Show Episode

Source URL: https://www.scribbr.com/citation/generator/cite/tv-show-episode/

Required:
- Source type: TV show episode
- Collection title, typically TV series name

Recommended:
- Contributors
- Issued date

Other fields:
- Title, typically episode title
- Season
- Episode
- Medium
- Accessed date
- Publisher
- Source
- URL
- Note

### 33. Video

Source URL: https://www.scribbr.com/citation/generator/cite/video/

Required:
- Source type: Video
- Title

Recommended:
- Container title, typically platform/channel/site
- Contributors
- Issued date

Other fields:
- Accessed date
- URL
- Note

### 34. Webpage

Source URL: https://www.scribbr.com/citation/generator/cite/webpage/

Required:
- Source type: Webpage
- Title

Recommended:
- Contributors
- Issued date
- URL

Other fields:
- Container title, displayed conceptually as website name
- Accessed date
- Note

### 35. Website

Source URL: https://www.scribbr.com/citation/generator/cite/website/

Required:
- Source type: Website
- Title

Recommended:
- Issued date
- Accessed date
- URL

Other fields:
- Publisher
- Note

### 36. Wiki Entry

Source URL: https://www.scribbr.com/citation/generator/cite/wiki-entry/

Required:
- Source type: Wiki entry / Wikipedia article
- Title

Recommended:
- Container title
- Issued date
- URL

Other fields:
- Accessed date
- Note

## Most Common Field Sets

Web sources usually ask for:
- Source type
- Title or content
- Container title / website / platform / publication name
- Contributors
- Issued date
- Accessed date
- URL
- Note

Books and book-like sources usually ask for:
- Source type
- Title
- Contributors
- Edition
- Volume
- Medium
- Issued date
- Publisher
- Publisher place
- DOI / PDF URL / URL
- Note

Articles usually ask for:
- Source type
- Title
- Container title, such as journal/newspaper/magazine name
- Contributors
- Date
- Volume/issue/number where relevant
- Page range where relevant
- DOI / URL where relevant
- Note

Audio/video sources usually ask for:
- Source type
- Title or episode title
- Collection title for episodes
- Contributors
- Season/episode where relevant
- Medium
- Issued/accessed dates
- Publisher/source/platform
- URL
- Note

Legal/specialized sources add domain-specific fields:
- Patent adds number, jurisdiction, authority, and required contributors/date.
- Thesis adds genre, submitted date, publisher/institution, DOI/PDF URL.
- Dataset adds version, medium, status, publisher, DOI/PDF URL/URL.
