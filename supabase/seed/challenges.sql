-- Seed challenge bank (~60 challenges across categories and difficulties)

insert into public.challenges (prompt, category, difficulty) values
-- Beginner / Everyday
('What is your favorite food?', 'everyday', 'beginner'),
('Describe your morning routine.', 'everyday', 'beginner'),
('What do you do on weekends?', 'everyday', 'beginner'),
('Tell me about your hometown.', 'everyday', 'beginner'),
('What is your favorite season and why?', 'everyday', 'beginner'),
('Describe your perfect Sunday.', 'everyday', 'beginner'),
('What hobbies do you enjoy?', 'everyday', 'beginner'),
('Tell me about a book or movie you like.', 'everyday', 'beginner'),
('What is your favorite way to relax?', 'everyday', 'beginner'),
('Describe your ideal vacation.', 'everyday', 'beginner'),

-- Beginner / Opinion
('Do you prefer tea or coffee?', 'opinion', 'beginner'),
('Is it better to live in a city or countryside?', 'opinion', 'beginner'),
('Do you like working from home?', 'opinion', 'beginner'),
('Are pets important in a family?', 'opinion', 'beginner'),

-- Intermediate / Everyday
('Describe a typical day at your job.', 'everyday', 'intermediate'),
('What makes a good friend?', 'everyday', 'intermediate'),
('How do you stay healthy?', 'everyday', 'intermediate'),

-- Intermediate / Opinion
('Why do you like your current job?', 'opinion', 'intermediate'),
('Is money necessary for happiness?', 'opinion', 'intermediate'),
('Should people work remotely?', 'opinion', 'intermediate'),
('Is social media good for society?', 'opinion', 'intermediate'),
('Would you rather be rich or famous?', 'opinion', 'intermediate'),
('What makes someone successful?', 'opinion', 'intermediate'),
('Is it better to be a generalist or specialist?', 'opinion', 'intermediate'),

-- Intermediate / Storytelling
('Tell me about a time you failed.', 'storytelling', 'intermediate'),
('Describe a memorable trip you took.', 'storytelling', 'intermediate'),
('Tell me about a challenge you overcame.', 'storytelling', 'intermediate'),
('Share a time you helped someone.', 'storytelling', 'intermediate'),
('Tell me about your proudest achievement.', 'storytelling', 'intermediate'),

-- Intermediate / Work
('What makes a good manager?', 'work', 'intermediate'),
('How do you handle stress at work?', 'work', 'intermediate'),
('Describe your ideal work environment.', 'work', 'intermediate'),
('What skills are most important in your field?', 'work', 'intermediate'),

-- Intermediate / Interview
('Tell me about yourself.', 'interview', 'intermediate'),
('Why do you want this role?', 'interview', 'intermediate'),
('Describe a time you worked in a team.', 'interview', 'intermediate'),
('What is your greatest strength?', 'interview', 'intermediate'),

-- Intermediate / Imagine
('You wake up on Mars. What do you do?', 'imagine', 'intermediate'),
('If you could have dinner with anyone, who would it be?', 'imagine', 'intermediate'),
('If you won the lottery, what would you do?', 'imagine', 'intermediate'),

-- Advanced / Opinion
('Is technological progress always beneficial?', 'opinion', 'advanced'),
('Should universities be free for everyone?', 'opinion', 'advanced'),
('Is ambition more important than contentment?', 'opinion', 'advanced'),
('Do we rely too much on technology?', 'opinion', 'advanced'),

-- Advanced / Debate
('Social media has made society less social. Agree or disagree?', 'debate', 'advanced'),
('Remote work hurts company culture. Agree or disagree?', 'debate', 'advanced'),
('Artificial intelligence will do more harm than good. Agree or disagree?', 'debate', 'advanced'),
('Experience is more valuable than education. Agree or disagree?', 'debate', 'advanced'),

-- Advanced / Storytelling
('Tell me about a decision you regret and what you learned.', 'storytelling', 'advanced'),
('Describe a time you had to persuade someone.', 'storytelling', 'advanced'),
('Tell me about a project that didn''t go as planned.', 'storytelling', 'advanced'),

-- Advanced / Work
('How would you improve your industry?', 'work', 'advanced'),
('What is the biggest challenge facing your profession?', 'work', 'advanced'),

-- Advanced / Interview
('Tell me about a conflict you resolved at work.', 'interview', 'advanced'),
('Where do you see yourself in five years?', 'interview', 'advanced'),
('Describe a time you showed leadership.', 'interview', 'advanced'),

-- Expert
('Defend an opinion that you personally disagree with.', 'debate', 'expert'),
('Argue that failure is more valuable than success.', 'debate', 'expert'),
('Convince me that the opposite of your belief is true.', 'debate', 'expert'),
('If you could change one law, what would it be and why?', 'opinion', 'expert'),
('Explain a complex topic from your field to a child.', 'work', 'expert'),
('What ethical dilemma have you faced and how did you resolve it?', 'storytelling', 'expert');
