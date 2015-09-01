module DraftPunkHelper
  def summarize_draft_changes(draft_diff)
    changed = []
    draft_diff.except("id", :draft_status, :class_info).each do |k,v|
      if v.is_a?(Array)
        changed << summarize_association_changes(k,v)
      else
        changed << k
      end
    end
    return "Changed: #{changed.compact.to_sentence}" if changed.present?
  end

  def summarize_association_changes(assoc, values)
    return assoc if did_association_change?(values)
  end

  def did_association_change?(children)
    return true if children.is_a?(Hash) && children[:diff_status] !=:unchanged
    children.each do |obj|
      obj.each do |k,v|
        if v.is_a?(Array) #nested association
          return true if did_association_change?(v)
        elsif k == :draft_status
          return true if v != :unchanged
        end
      end
    end
    false
  end
end

ActionView::Base.send :include, DraftPunkHelper