class BoardConfiguration
  attr_reader :dev_columns, :qa_column, :qa_passed_column, :released_column, :qa_rejected_label, :blocked_label

  def initialize(dev_columns:, qa_column:, qa_passed_column:, released_column:, qa_rejected_label:, blocked_label:)
    @dev_columns = dev_columns
    @qa_column = qa_column
    @qa_passed_column = qa_passed_column
    @released_column = released_column
    @qa_rejected_label = qa_rejected_label
    @blocked_label = blocked_label
  end

end