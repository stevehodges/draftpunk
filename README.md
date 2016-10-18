# DraftPunk

DraftPunk allows editing of a draft version of an ActiveRecord model and its associations.

When it's time to edit, a draft version is created in the same table as the object. You can specify which associations should also be edited and stored with that draft version. All associations are stored in their native table.

When it's time to publish, any attributes changed on your draft object persist to the original object. All associated objects behave the same way. Any associated have_many objects which are deleted on the draft are deleted on the original object.

## Why this gem compared to similar gems?

I wrote this gem because other draft/publish gems had limitations that ruled them out in my use case. Here's a few reasons I ended up rolling my own:

1. This gem simply works with your existing database (plus one new column on your original object).
2. I tried using an approach that stores incremental changes in another table. For instance, some draft gems rely on a Versioning gem, or otherwise store incremental changes in the database.

    That gets super complicated, or simply don't work, with associations, nested associations, and/or if you want users to be able to *edit* those changes.
3. This gem works with Rails `accepts_nested_attributes`. That Rails pattern doesn't work when you pass in objects which aren't associated; for instance, if you try to save a new draft image on your Blog post via nested_attributes, Rails will throw a 404 error. It got nasty, fast, so I needed a solution that worked well with Rails.
4. I prefer to store drafts in the same table as the original. While this has a downside (see downsides, below), it means:
    1. Your draft acts like the original. You can execute all the same methods on it, reuse presenters, forms, form_objects, decorators, or anything else. It doesn't just quack like a duck, it **is** a duck.

    2. This prevents your table structure from getting out of sync. If you're using DraftPunk, when you add a new attribute to your model, or change a column, both your live/approved version and your draft version are affected. Using a different pattern, if they live in separate tables, you may need to run migrations on both tables (or, migrate the internals of a version diff if your draft gem relies on something like Paper Trail or VestalVersion)
  

### Downsides

Since DraftPunk saves in the same table as the original, your queries in those tables will return both approved and draft objects. In other words, without modifying your Rails app further, your BusinessController index action (in a typical rails app) will return drafts and approved objects. DraftPunk adds scopes to help you manage this. See the "What about the rest of the application? People are seeing draft businesses!" section below for two patterns to address this. 

## Usage

### Getting Started
To enable drafts for a model, first add an approved_version_id column (Integer), which will be used to track its draft.

Simply call requires_approval in your model to enable DraftPunk on that model and its associations:

    class Business << ActiveRecord::Base
      has_many :employees
      has_many :images
      has_one  :address
      has_many :vending_machines

      requires_approval 
    end

DraftPunk will generate drafts for all associations, by default. So when you create a draft Business, that draft will also have draft `employees`, `vending_machines`, `images`, and an `address`. The whole tree is recursively duplicated.

**Do not call `requires_approval` on Business's associated objects.** The behavior automatically cascades down til there are no more associations.

### Customize which associations have drafts created

Optionally, you can tell DraftPunk which associations the user will edit - the associations which should have a draft created.

If you only want the :address association to have a draft created, add a CREATES_NESTED_DRAFTS_FOR constant in your model:

    CREATES_NESTED_DRAFTS_FOR = [:address] # When creating a business's draft, only :address will have drafts created

To disable drafts for all assocations for this model, simply pass an empty array:

    CREATES_NESTED_DRAFTS_FOR = [] # When creating a business's draft, no associations will have drafts created

**WARNING: If you are setting associations via accepts_nested_attributes** _all changes to the draft, including associations, get set on the
draft object (as expected). If your form includes associated objects which weren't defined in requires_approval, your save will fail since
the draft object doesn't HAVE those associations to update! In this case, you should probably add that association to the
`associations` param when you call `requires_approval`._


### Working with a draft

So you have an ActiveRecord object:

    @business = Business.first

And you want it's editable version - its draft:

    @my_draft = @business.editable_version   #If @business doesn't have a draft yet, it creates one for you. 

Now you can edit the draft. Perhaps in your controller, you have:

    def edit
      @my_draft = @business.editable_version
      render 'form'
    end

In the view (or even in rails console), you'll want to be editing that draft version. For instance, pass your draft into the business's form, and it'll just work!

    form_for @my_draft

And, voila, the user is editing the draft.

Your update action might look like so:

    def update
      @my_draft = Business.find(params[:id])
      .... do some stuff here
    end

So your draft is automagically getting updated.

Say your `@business` has a `name` attribute:

    @business.name
    => "DraftPunk LLC"

Ok, you just incorperated so your name changed.

    @my_draft = @business.editable_version
    @my_draft.name = "DraftPunk Incorperated"
    @my_draft.save

At this point, that change is only saved on the draft version of your business. The original business still has the name DraftPunk LLC.

#### Publish the draft - aka making your changes live

So you want to make your changes live:

    @business.name
    => "DraftPunk LLC"
    @business.draft.name
    => "DraftPunk Incorperated"    
    @business.publish_draft!
    @business.name
    => "DraftPunk Incorperated"    

**All of the @business associations copied from the draft**. More correctly, the foreign_keys on has_many associations are changed, set to the original object (@business) id. All the old associations (specified in requires_approval) on @business are destroyed.

At this point, the draft is destroyed. Next time you call `editable_version`, a draft will be created for you.

### Tracking drafts
Your original model has a few methods available:

    @business.id
    => 1    
    @draft = @business.draft
    => Business(id: 2, ...)
    @draft.approved_version
    => Business(id: 1, ...)
    @draft.is_draft?
    => true
    @draft.has_draft?
    => false
    @business.is_draft?
    => false
    @business.has_draft?
    => true

Your associations can have this behavior, too, which could be useful in your application. If you want your draft associations to track their live version, add an `approved_version_id` column (Integer) to each table. You'll have all the methods demonstrated above. This also allows you to access a child association directly, ie. 

    @live_image = @business.images.first
    => Image(id: 1, ...)
    @draft_image = @business.draft.images.first
    => Image(id: 2, ...)

At this point, if you don't have `approved_version_id` on the `images` table, there's no way for you to know that @draft_image was originally a copy of @live_image. If you have approved_version_id on your table, you can call:

    @draft_image.approved_version
    => Image(id: 1, ...)
    @live_image.draft
    => Image(id: 2, ...)

You now know for certain that the two are associated, which could be useful in your app.

### Free ActiveRecord scopes
All models which have `approved_version_id` also have these scopes: `approved` and `draft`.

## What about the rest of the application? People are seeing draft businesses!

You can implement this in a variety of ways. Here's two approaches:

#### Set a Rails `default_scope` on your model.

This is the quickest, most DRY way to address this, but of course default_scopes aren't always the right answer for every Rails app.

    default_scope Business.approved

Then, any ActiveRecord queries for Business will be scoped to only approved models. Your `draft` scope, and `draft` association will ignore this scope, so @business.draft and Business.draft will both continue to return draft objects. 


#### Or, modify your controllers to use the `approved` scope
Alternately, you may want to modify your controllers to only access _approved_ objects. For instance, your business controller should use that `approved` scope when it looks up businesses. i.e.

    class BusinessesController < ApplicationController
      def index
        @businesses = Business.approved.all
        ... more code
      end
    end

## TODO: Customizing Association associations (grandchildren) using accepts_nested_drafts_for

## TODO: Customizing approvable_attributes, changes_require_approval

## Options before creating a draft

When calling `requires_approval`, you can pass a `nullify` option to set attributes to null once the draft is created:

    requires_approval nullify: [:subdomain]

This could be useful if your model has an attribute which should not persist. In this example, each Business has a unique subdomain (ie. business_name.foo.com ). By nullifying this out, the subdomain on the draft would be nil. 

### Before create callback

If you define a method on your model called `before_create_draft`, that method will be executed before the draft is created.

You can access `self` (which is the DRAFT version being created), or the `temporary_approved_object` (the original object) in this method

    def before_create_draft
      logger.warn "#{self.name} is being created from #{temporary_approved_object.class.name} ##{temporary_approved_object.id}" # outputs: DerpCorp is being created from Business #1
    end

### After create callback

If you define a method on your model called `after_create_draft`, that method will be executed before the draft is created. This is useful in cases when you need a fully set-up draft to modify. For instance, after all of its associations have been set.

You can access `self` (which is the DRAFT version being created), or the `temporary_approved_object` (the original object) in this method

**Note that you are responsible for any saves needed**. draft_punk does not save again after your after_create executes

## Options before publishing a draft

### Before publish draft method

If you define a method on your model called `before_publish_draft`, that method will be executed before the draft is published. Specifically, it happens after all attributes are copied from the draft to the approved version, and right before the approved version is saved. This allows you to do whatever you'd like to the model before it is saved.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'draft_punk'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install draft_punk

## Contributing

1. Fork it ( https://github.com/stevehodges/draft_punk/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Be consistent with the rest of this repo. Write thorough tests (rspec) and documentation (yard)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request
